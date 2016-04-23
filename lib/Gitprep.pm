use 5.010001;
package Gitprep;
use Mojo::Base 'Mojolicious';

use Carp 'croak';
use DBIx::Custom;
use Gitprep::API;
use Gitprep::Git;
use Gitprep::Manager;
use Scalar::Util 'weaken';
use Validator::Custom;
use Time::Moment;

# Digest::SHA loading to Mojo::Util if not loaded
{
  package Mojo::Util;
  eval {require Digest::SHA; import Digest::SHA qw(sha1 sha1_hex)};
}

our $VERSION = 'v2.00_dev';

has 'dbi';
has 'git';
has 'manager';
has 'vc';

use constant BUFFER_SIZE => 8192;

sub data_dir {
  my $self = shift;
  
  my $data_dir = $self->config('data_dir');
  
  return $data_dir;
}

sub rep_home {
  my $self = shift;
  
  my $rep_home = $self->data_dir . "/rep";
  
  return $rep_home;
}

sub rep_info {
  my ($self, $user, $project) = @_;
  
  my $info = {};
  $info->{user} = $user;
  $info->{project} = $project;
  $info->{git_dir} = $self->rep_home . "/$user/$project.git";
  
  return $info;
}

sub work_rep_home {
  my $self = shift;
  
  my $work_rep_home = $self->data_dir . "/work";
  
  return $work_rep_home;
}

sub work_rep_info {
  my ($self, $user, $project) = @_;
  
  my $info = {};
  $info->{user} = $user;
  $info->{project} = $project;
  $info->{git_dir} = $self->work_rep_home . "/$user/$project/.git";
  $info->{work_tree} = $self->work_rep_home . "/$user/$project";
  
  return $info;
}

sub startup {
  my $self = shift;
  
  # Config file
  $self->plugin('INIConfig', {ext => 'conf'});
  
  # Config file for developper
  unless ($ENV{GITPREP_NO_MYCONFIG}) {
    my $my_conf_file = $self->home->rel_file('gitprep.my.conf');
    $self->plugin('INIConfig', {file => $my_conf_file}) if -f $my_conf_file;
  }
  
  # Listen
  my $conf = $self->config;
  my $listen = $conf->{hypnotoad}{listen} ||= ['http://*:10020'];
  $listen = [split /,/, $listen] unless ref $listen eq 'ARRAY';
  $conf->{hypnotoad}{listen} = $listen;
  
  # Data directory
  my $data_dir = $ENV{GITPREP_DATA_DIR} ? $ENV{GITPREP_DATA_DIR} : $self->home->rel_file('data');
  $self->config(data_dir => $data_dir);
  
  # Git
  my $git = Gitprep::Git->new;
  $git->app($self);
  weaken $git->{app};
  my $git_bin
    = $conf->{basic}{git_bin} ? $conf->{basic}{git_bin} : $git->search_bin;
  if (!$git_bin || ! -e $git_bin) {
    $git_bin ||= '';
    my $error = "Can't detect or found git command ($git_bin)."
      . " set git_bin in gitprep.conf";
    $self->log->error($error);
    croak $error;
  }
  $git->bin($git_bin);
  
  # Repository Manager
  my $manager = Gitprep::Manager->new;
  $manager->app($self);
  weaken $manager->{app};
  $self->manager($manager);
  
  # authorized_keys file
  my $authorized_keys_file = $conf->{basic}{authorized_keys_file};
  unless (defined $authorized_keys_file) {
    if (defined $ENV{HOME}) {
      $authorized_keys_file = "$ENV{HOME}/.ssh/authorized_keys";
    }
  }
  if (defined $authorized_keys_file) {
    $self->manager->authorized_keys_file($authorized_keys_file);
  }
  else {
    $self->app->log->warn(qq/Config "authorized_keys_file" can't be detected/);
  }
  
  # Repository home
  my $rep_home = "$data_dir/rep";
  unless (-d $rep_home) {
    mkdir $rep_home
      or croak "Can't create directory $rep_home: $!";
  }
  
  # Time Zone
  if (my $time_zone = $conf->{basic}{time_zone}) {
    
    if ($time_zone =~ /^([\+-])?([0-9]?[0-9]):([0-9][0-9])$/) {
      my $sign = $1 || '';
      my $hour = $2;
      my $min = $3;
      
      my $time_zone_second = $sign . ($hour * 60 * 60) + ($min * 60);
      $git->time_zone_second($time_zone_second);
    }
    else {
      $self->log->warn("Bad time zone $time_zone. Time zone become GMT");
    }
  }
  $self->git($git);
  
  # DBI
  my $db_file = "$data_dir/gitprep.db";
  my $dbi = DBIx::Custom->connect(
    dsn => "dbi:SQLite:database=$db_file",
    connector => 1,
    option => {sqlite_unicode => 1, sqlite_use_immediate_transaction => 1}
  );
  $self->dbi($dbi);
  
  # Database file permision
  if (my $user = $self->config->{hypnotoad}{user}) {
    my $uid = (getpwnam $user)[2];
    chown $uid, -1, $db_file;
  }
  if (my $group = $self->config->{hypnotoad}{group}) {
    my $gid = (getgrnam $group)[2];
    chown -1, $gid, $db_file;
  }
  
  # Model
  my $models = [
    {
      table => 'user',
      primary_key => 'row_id'
    },
    {
      table => 'ssh_public_key',
      primary_key => 'row_id',
      join => [
        'left join user on ssh_public_key.user = user.row_id'
      ]
    },
    {
      table => 'project',
      primary_key => 'row_id',
      join => [
        'left join user on project.user = user.row_id'
      ]
    },
    {
      table => 'collaboration',
      primary_key => 'row_id',
      join => [
        'left join user on collaboration.user = user.row_id',
        'left join project on collaboration.project = project.row_id',
      ]
    },
    {
      table => 'pull_request',
      primary_key => 'row_id',
      join => [
        'left join user on pull_request.open_user = user.row_id'
      ]
    },
    {
      table => 'pull_request_message',
      primary_key => 'row_id',
      join => [
        'left join user on pull_request_message.user = user.row_id',
        'left join pull_request on pull_request_message.pull_request = pull_request.row_id'
      ]
    }
  ];
  $dbi->create_model($_) for @$models;
  $dbi->setup_model;

  # Validator
  my $vc = Validator::Custom->new;
  $self->vc($vc);
  $vc->register_constraint(
    user_name => sub {
      my $value = shift;
      
      return ($value || '') =~ /^[a-zA-Z0-9_\-]+$/;
    },
    project_name => sub {
      my $value = shift;
      return 0 unless defined $value;
      return 0 if $value eq '.' || $value eq '..';

      return ($value || '') =~ /[a-zA-Z0-9_\-\.]+$/;
    }
  );
  
  $vc->add_check(project_name => sub {
    my ($vc, $value) = @_;
    
    return 0 unless defined $value;
    return 0 if $value eq '.' || $value eq '..';
    
    return ($value || '') =~ /[a-zA-Z0-9_\-\.]+$/;
  });
  $vc->add_check(user_name => sub {
    my ($vc, $value) = @_;
    
    return ($value || '') =~ /^[a-zA-Z0-9_\-]+$/;
  });
  
  # Basic auth plugin
  $self->plugin('BasicAuth');

  {
    my $r = $self->routes;

    # DBViewer(only development)
    # /dbviewer
    if ($self->mode eq 'development') {
      eval {
        $self->plugin(
          'DBViewer',
          dsn => "dbi:SQLite:database=$db_file"
        );
      };
    }
    
    # Auto route
    {
      my $r = $r->under(sub {
        my $self = shift;
        
        my $api = $self->gitprep_api;
        
        # Authentication
        {
          my $path = $self->req->url->path->parts->[0] || '';
          
          # Admin
          if ($path eq '_admin' && !$api->logined_admin) {
            $self->redirect_to('/');
            return;
          }
        }
        
        return 1; 
      });
      
      # Auto routes
      $self->plugin('AutoRoute', route => $r);
      
      # Custom routes
      {
        # Show ssh keys
        $r->get('/(:user).keys' => sub { shift->render_maybe('/user-keys') });
        
        # User
        my $r = $r->route('/:user');
        {
          # Home
          $r->get('/' => [format => 0] => sub { shift->render_maybe('/user') });
          
          # Settings
          $r->get('/_settings' => sub { shift->render_maybe('/user-settings') });
          
          # SSH keys
          $r->any('/_settings/ssh' => sub { shift->render_maybe('/user-settings/ssh') });
        }

        # Smart HTTP
        {
          my $r = $r->route('/(#project).git');
          
          {
            my $r = $r->under(sub {
              my $self = shift;
              
              my $api = $self->gitprep_api;
              my $user = $self->param('user');
              my $project = $self->param('project');
              my $private = $self->app->manager->is_private_project($user, $project);
              
              # Basic auth when push request
              my $service = $self->param('service') || '';
              if ($service eq 'git-receive-pack' || $private) {
                
                $self->basic_auth("Git Area", sub {
                  my ($auth_user, $auth_password) = @_;
                  
                  if (!defined $auth_user || !length $auth_user) {
                    $self->app->log->warn("Authentication: User name is empty");
                  }
                  
                  $auth_user = '' unless defined $auth_user;
                  $auth_password = '' unless defined $auth_password;
                  
                  my $is_valid =
                    ($user eq $auth_user || $api->is_collaborator($user, $project, $auth_user))
                    && $api->check_user_and_password($auth_user, $auth_password);
                  
                  return $is_valid;
                });
              }
              else {
                return 1;
              }
            });
            
            # /
            $r->get('/')->to(cb => sub {
              my $self = shift;
              
              my $user = $self->param('user');
              my $project = $self->param('project');
              
              $self->redirect_to("/$user/$project");
            });
            
            # /info/refs
            $r->get('/info/refs' => sub { shift->render_maybe('smart-http/info-refs') });
            
            # /git-upload-pack or /git-receive-pack
            $r->any('/git-(:service)'
              => [service => qr/(?:upload-pack|receive-pack)/]
              => sub { shift->render_maybe('smart-http/service') }
            );
            
            # Static file
            $r->get('/(*Path)' => sub { shift->render_maybe('smart-http/static') });
          }
        }
                
        # Project
        {
          my $r = $r->route('/#project');
          
          {
            my $r = $r->under(sub {
              my $self = shift;
              
              # API
              my $api = $self->gitprep_api;
              
              # Private
              my $user = $self->param('user');
              my $project = $self->param('project');
              my $private = $self->app->manager->is_private_project($user, $project);
              if ($private) {
                if ($api->can_access_private_project($user, $project)) {
                  return 1;
                }
                else {
                  $self->render('private');
                  return 0;
                }
              }
              else {
                return 1;
              }
            });
            
            # Home
            $r->get('/' => sub { shift->render_maybe('/tree') });

            # Pull requests
            $r->get('/pulls' => sub { shift->render_maybe('/pulls') })->to(tab => 'pulls');
            
            # Pull request
            $r->any('/pull/:row_id' => sub { shift->render_maybe('/pull') })->to(tab => 'pulls');
            
            # Commit
            $r->get('/commit/*diff' => sub { shift->render_maybe('/commit') });

            # Commits
            $r->get('/commits/*rev_file' => sub { shift->render_maybe('/commits') });
            
            # Branches
            $r->any('/branches/:display' => {display => undef} => sub { shift->render_maybe('/branches') });

            # Tags
            $r->get('/tags' => sub { shift->render_maybe('/tags') });

            # Tree
            $r->get('/tree/*rev_dir' => sub { shift->render_maybe('/tree') });
            
            # Blob
            $r->get('/blob/*rev_file' => sub { shift->render_maybe('/blob') });
            
            # Sub module
            $r->get('/submodule/*rev_file' => sub { shift->render_maybe('/submodule') });

            # Raw
            $r->get('/raw/*rev_file' => sub { shift->render_maybe('/raw') });

            # Blame
            $r->get('/blame/*rev_file' => sub { shift->render_maybe('/blame') });
            
            # Archive
            # Archive
            $r->get('/archive/(*rev).tar.gz' => sub { shift->render_maybe('/archive') })->to(archive_type => 'tar');
            $r->get('/archive/(*rev).zip' => sub { shift->render_maybe('/archive') })->to(archive_type => 'zip' );
            
            # Compare
            $r->any('/compare' => sub { shift->render_maybe('/compare') });
            $r->any(
              '/compare/(:rev1)...(:rev2)'
              => [rev1 => qr/[^\.]+/, rev2 => qr/[^\.]+/]
              => sub { shift->render_maybe('/compare') }
            );
            $r->any('/compare/(:rev2)' => sub { shift->render_maybe('/compare') });
            
            # Settings
            {
              my $r = $r->route('/settings')->to(tab => 'settings');
              
              # Settings
              $r->any('/' => sub { shift->render_maybe('/settings') });
              
              # Collaboration
              $r->any('/collaboration' => sub { shift->render_maybe('/settings/collaboration') });
            }
            
            # Fork
            $r->any('/fork' => sub { shift->render_maybe('/fork') });
            
            # Network
            {
              my $r = $r->route('/network')->to(tab => 'graph');
              
              # Network
              $r->get('/' => sub { shift->render_maybe('/network') });

              # Network Graph
              $r->get('/graph/(*rev1)...(*rev2_abs)' => sub { shift->render_maybe('/network/graph') });
            }

            # Import branch
            $r->any('/import-branch/:remote_user/:remote_project' => sub { shift->render_maybe('/import-branch') });
            
            # Get branches and tags
            $r->get('/api/revs' => sub { shift->render_maybe('/api/revs') });
          }
        }
      }
    }
  }

  # Helper
  {
    # API
    $self->helper(gitprep_api => sub { Gitprep::API->new(shift) });
  }
  
  # set scheme to https when X-Forwarded-HTTPS header is specified
  # This is for the backword compatible only. Now X-Forwarded-Proto is used for this purpose
  $self->hook(before_dispatch => sub {
    my $c = shift;
    if ($c->req->headers->header('X-Forwarded-HTTPS')) {
      $c->req->url->base->scheme('https');
      $c->app->log->warn("X-Forwarded-HTTPS header is DEPRECATED! use X-Forwarded-Proto instead.");
    }
  });

  # Set auto_decompress for Smart HTTP(I don't know this reasone)
  $self->hook('after_build_tx' => sub {
    my ($tx, $app) = @_;
    
    $tx->req->content->auto_decompress(1);
  });

  # Reverse proxy support
  my $reverse_proxy_on = $self->config->{reverse_proxy}{on};
  my $path_depth = $self->config->{reverse_proxy}{path_depth};
  if ($reverse_proxy_on) {
    $ENV{MOJO_REVERSE_PROXY} = 1;
    if ($path_depth) {
      $self->hook('before_dispatch' => sub {
        my $self = shift;
        for (1 .. $path_depth) {
          my $prefix = shift @{$self->req->url->path->parts};
          push @{$self->req->url->base->path->parts}, $prefix;
        }
      });
    }
  }
  
  # Smart HTTP Buffer size
  $ENV{GITPREP_SMART_HTTP_BUFFER_SIZE} ||= 16384;
}

1;
