use 5.010001;
package Gitprep;

use Encode ();
# Fix CGI PATH_INFO encoding bug
eval { $ENV{PATH_INFO} = Encode::decode('UTF-8', $ENV{PATH_INFO}) };

use Mojo::Base 'Mojolicious';

use Carp 'croak';
use DBIx::Custom;
use Gitprep::API;
use Gitprep::Git;
use Gitprep::Manager;
use Scalar::Util 'weaken';
use Validator::Custom;
use Time::Moment;
use Email::Sender::Transport::SMTP;
use Email::Sender::Transport::Sendmail;

# Digest::SHA loading to Mojo::Util if not loaded
{
  package Mojo::Util;
  eval {require Digest::SHA; import Digest::SHA qw(sha1 sha1_hex)};
}

our $VERSION = 'v2.6.2';

our $user_re = qr/[a-zA-Z0-9_\-]+/;
our $project_re = qr/[a-zA-Z0-9_\-\.]+/;

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
  my ($self, $user_id, $project_id) = @_;
  
  my $info = {};
  $info->{user} = $user_id;
  $info->{project} = $project_id;
  $info->{git_dir} = $self->rep_home . "/$user_id/$project_id.git";
  
  return $info;
}

sub work_rep_home {
  my $self = shift;
  
  my $work_rep_home = $self->data_dir . "/work";
  
  return $work_rep_home;
}

sub work_rep_info {
  my ($self, $user_id, $project_id) = @_;
  
  my $info = {};
  $info->{user} = $user_id;
  $info->{project} = $project_id;
  $info->{git_dir} = $self->work_rep_home . "/$user_id/$project_id/.git";
  $info->{work_tree} = $self->work_rep_home . "/$user_id/$project_id";
  
  return $info;
}

sub wiki_rep_info {
  my ($self, $user_id, $project_id) = @_;
  
  my $info = {};
  $info->{user} = $user_id;
  $info->{project} = $project_id;
  $info->{git_dir} = $self->rep_home . "/$user_id/$project_id.wiki.git";
  
  return $info;
}

sub wiki_work_rep_info {
  my ($self, $user_id, $project_id) = @_;
  
  my $info = {};
  $info->{user} = $user_id;
  $info->{project} = $project_id;
  $info->{git_dir} = $self->work_rep_home . "/$user_id/$project_id.wiki/.git";
  $info->{work_tree} = $self->work_rep_home . "/$user_id/$project_id.wiki";
  
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

  my $conf = $self->config;

  # Set-up secret passphrase.
  if ($conf->{basic}{secret}) {
    $self->secrets([$conf->{basic}{secret}]);
  }

  # Configure logging.
  if (my $mojo_log = $conf->{basic}{mojo_log_file_path}) {
     my $log = Mojo::Log->new(path => $mojo_log, level => 'trace');
     $self->log($log);
  }
  if (my $access_log = $conf->{basic}{access_log_file_path} ) {
     $self->plugin(AccessLog => log => $access_log);
  }

  # Listen
  my $listen = $conf->{hypnotoad}{listen} ||= ['http://*:10020'];
  $listen = [split /,/, $listen] unless ref $listen eq 'ARRAY';
  $conf->{hypnotoad}{listen} = $listen;
  
  # Data directory
  my $data_dir = $ENV{GITPREP_DATA_DIR} ? $ENV{GITPREP_DATA_DIR} : $self->home->rel_file('data');
  $self->config(data_dir => $data_dir);

  if (my $custom_templates = $conf->{templates}{custom_template_folder}) {
    die "$custom_templates folder not found or not writable! Giving up ..." unless (-d $custom_templates && -w $custom_templates);
    unshift(@{$self->renderer->paths}, $custom_templates);
  }

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
  if (my $user_id = $conf->{hypnotoad}{user}) {
    my $uid = (getpwnam $user_id)[2];
    chown $uid, -1, $db_file;
  }
  if (my $group = $conf->{hypnotoad}{group}) {
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
      table => 'issue',
      join => [
        'left join project on issue.project = project.row_id',
        'left join user as project__user on project.user = project__user.row_id',
        'left join pull_request on issue.pull_request = pull_request.row_id',
        'left join user as open_user on issue.open_user = open_user.row_id',
        'left join project as pull_request__base_project on pull_request.base_project = pull_request__base_project.row_id',
        'left join user as pull_request__base_project__user'
          . ' on pull_request__base_project.user = pull_request__base_project__user.row_id',
        'left join project as pull_request__target_project on pull_request.target_project = pull_request__target_project.row_id',
        'left join user as pull_request__target_project__user'
          . ' on pull_request__target_project.user = pull_request__target_project__user.row_id'

      ]
    },
    {
      table => 'issue_message',
      primary_key => 'row_id',
      join => [
        'left join user on issue_message.user = user.row_id',
        'left join issue on issue_message.issue = issue.row_id'
      ]
    },
    {
      table => 'pull_request',
      primary_key => 'row_id',
      join => [
        'left join user as open_user on pull_request.open_user = open_user.row_id',
        'left join project as base_project on pull_request.base_project = base_project.row_id',
        'left join user as base_project__user'
          . ' on base_project.user = base_project__user.row_id',
        'left join project as target_project on pull_request.target_project = target_project.row_id',
        'left join user as pull_request__target_project__user'
          . ' on target_project.user = target_project__user.row_id'
      ]
    },
    {
      table => 'label',
      primary_key => 'row_id',
      join => [
        'left join project on label.project = project.row_id',
        'left join user as project__user on project.user = project__user.row_id'
      ]
    },
    {
      table => 'issue_label',
      primary_key => 'row_id',
      join => [
        'left join label on issue_label.label = label.row_id'
      ]
    },
    {
      table => 'wiki'
    },
    {
      table => 'subscription',
      primary_key => 'row_id',
      join => [
        'left join issue as subscription__issue on subscription.issue = subscription__issue.row_id',
        'left join user as subscription__user on subscription.user = subscription__user.row_id'
      ]
    },
    {
      table => 'watch',
      primary_key => 'row_id',
      join => [
        'left join user as watch__user on watch.user = watch__user.row_id',
        'left join project as watch__project on watch.project = watch__project.row_id'
      ]
    }
  ];
  $dbi->create_model($_) for @$models;

  # Validator
  my $vc = Validator::Custom->new;
  $self->vc($vc);
  $vc->register_constraint(
    user_name => sub {
      my $value = shift;
      
      return ($value || '') =~ /^$user_re$/;
    },
    project_name => sub {
      my $value = shift;
      return 0 unless defined $value;
      return 0 if $value eq '.' || $value eq '..';

      return ($value || '') =~ /$project_re$/;
    }
  );
  
  $vc->add_check(project_name => sub {
    my ($vc, $value) = @_;
    
    return 0 unless defined $value;
    return 0 if $value eq '.' || $value eq '..';
    
    return ($value || '') =~ /$project_re$/;
  });
  $vc->add_check(user_name => sub {
    my ($vc, $value) = @_;
    
    return ($value || '') =~ /^$user_re$/;
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
          my $repo = $self->req->url->path->parts->[1] || '';
          my $hide_from_public = $conf->{basic}{hide_from_public};
          my $request_login = 0;

          my $service = $self->param('service');

          # repositories need login?
          if ($hide_from_public)
          {
            $request_login = 1;

            if ($api->logined) {
              $request_login = 0;
            }

            if ($path eq '_login' && !$api->logined_admin) {
              $request_login = 0;
            }

            # if the repo ends with .git, don't request_login, but go on to /<#project>.git
            if ($repo =~ /\.git$/) {
              $request_login = 0;
            }
          }

          # Admin
          if ($path eq '_admin' && !$api->logined_admin) {
            $request_login = 1;
          }

          if ($request_login == 1 && $path ne 'reset-password') {
            $self->redirect_to('/_login');
            return;
          }
        }
        
        return 1; 
      });
      
      # Auto routes
      $self->plugin('AutoRoute', route => $r);
      
      # Custom routes
      {
        # User
        my $r = $r->any('/:user');
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
          my $r = $r->any('/<#project>.git');
          
          {
            my $r = $r->under(sub {
              my $self = shift;
              
              my $api = $self->gitprep_api;
              my $user_id = $self->param('user');
              my $project_id = $self->param('project');
              $self->log->info("user: $user_id project $project_id");
              my $private = $self->app->manager->is_private_project($user_id, $project_id);
              

              if ($conf->{basic}{hide_from_public})
              {
                $private = 1;
              }

              # Basic auth when push request
              my $service = $self->param('service') || '';
              if ($service eq 'git-receive-pack' || $private) {
                
                $self->basic_auth("Git Area", sub {
                  my ($auth_user_id, $auth_password) = @_;
                  
                  if (!defined $auth_user_id || !length $auth_user_id) {
                    $self->app->log->warn("Authentication: User name is empty");
                  }
                  
                  $auth_user_id = '' unless defined $auth_user_id;
                  $auth_password = '' unless defined $auth_password;
                  
                  my $is_valid =
                    ($user_id eq $auth_user_id || $api->is_collaborator($auth_user_id, $user_id, $project_id))
                    && $api->check_user_and_password($auth_user_id, $auth_password);
                  
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
              
              my $user_id = $self->param('user');
              my $project_id = $self->param('project');
              
              $self->redirect_to("/$user_id/$project_id");
            });
            
            # /info/refs
            $r->get('/info/refs' => sub {
                shift->render_maybe('smart-http/info-refs') 
            });
            
            # /git-upload-pack or /git-receive-pack
            $r->any(
                '/git-:service'
                    => [service => qr/(?:upload-pack|receive-pack)/]
                    => sub { shift->render_maybe('smart-http/service') }
            );
            
            # Static file
            $r->get('/<*Path>' => sub { shift->render_maybe('smart-http/static') });
          }
        }

        # Project
        {
          my $r = $r->any('/#project');
          
          {
            my $r = $r->under(sub {
              my $self = shift;
              
              # API
              my $api = $self->gitprep_api;
              
              # Private
              my $user_id = $self->param('user');
              my $project_id = $self->param('project');
              my $private = $self->app->manager->is_private_project($user_id, $project_id);
              if ($private) {
                if ($api->can_access_private_project($user_id, $project_id)) {
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
            
            # Issue
            $r->get('/issues' => sub { shift->render_maybe('/issues') })->to(tab => 'issues');

            # New issue
            $r->any('/issues/new' => sub { shift->render_maybe('/issues/new') })->to(tab => 'issues');
            $r->any('/issues/:number' => sub { shift->render_maybe('/issue') })->to(tab => 'issues');

            # Labels
            $r->any('/labels' => sub { shift->render_maybe('/labels') })->to(tab => 'issues');
            
            # Pull requests
            $r->get('/pulls' => sub { shift->render_maybe('/issues', pulls => 1) })->to(tab => 'pulls');
            
            # Pull request
            $r->get('/pull/<:number>.patch' => sub { shift->render_maybe('/issue') })->to(tab => 'pulls', patch => 1);
            $r->any('/pull/:number' => sub { shift->render_maybe('/issue') })->to(tab => 'pulls');
            $r->any('/pull/:number/:activetab' => [
              activetab => ['commits', 'files', 'contributors']
            ])->to(tab => 'pulls', cb => sub {
              shift->render_maybe('/issue')
            });

            # Wiki
            {
              my $r = $r->any('/wiki' => sub { shift->render_maybe('/wiki') })->to(tab => 'wiki');
              
              # Wiki top page
              $r->any('/');
              
              # Create page
              $r->any('/_new')->to(new => 1);
              
              # Show pages
              $r->any('/_pages')->to('list-pages' => 1);
              
              # Show wiki page
              $r->any('/:title');
              
              # Edit wiki page
              $r->any('/:title/_edit')->to(edit => 1);
              
              # Commits
              $r->get('/commits/*rev_file' => sub { shift->render_maybe('/commits') });
              
              # Commit
              $r->get('/commit/*diff' => sub { shift->render_maybe('/commit') });
              
              # Tree
              $r->get('/tree/*rev_dir' => sub { shift->render_maybe('/tree') });
              
              # Blob
              $r->get('/blob/*rev_file' => sub { shift->render_maybe('/blob') });
              
              # Raw
              $r->get('/raw/*rev_file' => sub { shift->render_maybe('/raw') });
              
              # Blame
              $r->get('/blame/*rev_file' => sub { shift->render_maybe('/blame') });
            }

            # Commit
            $r->get('/commit/*diff' => sub { shift->render_maybe('/commit') });

            # Commits
            $r->get('/commits/*rev_file' => sub { shift->render_maybe('/commits') });
            
            # Branches
            $r->any('/branches' => sub { shift->render_maybe('/branches') });

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
            $r->get('/archive/<*rev>.tar.gz' => sub { shift->render_maybe('/archive') })->to(archive_type => 'tar');
            $r->get('/archive/<*rev>.zip' => sub { shift->render_maybe('/archive') })->to(archive_type => 'zip' );
            
            # Compare
            $r->any('/compare' => sub { shift->render_maybe('/compare') });
            $r->any(
              '/compare/<:rev1>...<:rev2>'
              => [rev1 => qr/[^\.]+/, rev2 => qr/[^\.]+/]
              => sub { shift->render_maybe('/compare') }
            );
            $r->any('/compare/<:rev2>' => sub { shift->render_maybe('/compare') });
            
            # Settings
            {
              my $r = $r->any('/settings')->to(tab => 'settings');
              
              # Settings
              $r->any('/' => sub { shift->render_maybe('/settings') });
              
              # Collaboration
              $r->any('/collaboration' => sub { shift->render_maybe('/settings/collaboration') });
            }
            
            # Fork
            $r->any('/fork' => sub { shift->render_maybe('/fork') });
            
            # Network
            {
              my $r = $r->any('/network')->to(tab => 'graph');
              
              # Network
              $r->get('/' => sub { shift->render_maybe('/network') });

              # Network Graph
              $r->get('/graph/<*rev1>...<*rev2_abs>' => sub { shift->render_maybe('/network/graph') });
            }

            # Import branch
            $r->any('/import-branch/:remote_user/:remote_project' => sub { shift->render_maybe('/import-branch') });
            
            # Get branches and tags
            $r->get('/api/revs' => sub { shift->render_maybe('/api/revs') });

            # Subscription button.
            $r->get('/api/subscribe/:issue/:reason' => sub {
              my $self = shift;
              $self->render_maybe(template => '/api/subscribe',
                                  issue => $self->param('issue'),
                                  reason => $self->param('reason'));
             });

             # Watch button.
             $r->get('/api/watch/:state' => sub {
               my $self = shift;
               $self->render_maybe(template => '/api/watch',
                                   state => $self->param('state'));
             });
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

  $self->hook(before_dispatch => sub {
    my $c = shift;
    if (($c->req->headers->header('X-Forwarded-Proto') || '') eq 'https') {
      $c->req->url->base->scheme('https');
    }
    elsif ($c->req->headers->header('X-Forwarded-HTTPS')) {
      # Set scheme to https when X-Forwarded-HTTPS header is specified.
      # This is for backward compatibility only. Now X-Forwarded-Proto is
      # used for this purpose.
      $c->req->url->base->scheme('https');
      $c->app->log->warn("X-Forwarded-HTTPS header is DEPRECATED! use X-Forwarded-Proto instead.");
    }
  });

  # Set auto_decompress for Smart HTTP
  # HTTP request body of /smart-http/service is compressed.
  # If auto_decompress is not set, Smart HTTP fail.
  $self->hook('after_build_tx' => sub {
    my ($tx, $app) = @_;
    
    $tx->req->content->auto_decompress(1);
  });

  # Reverse proxy support
  $self->plugin('RequestBase');
  my $reverse_proxy_on = $conf->{reverse_proxy}{on};
  my $path_depth = $conf->{reverse_proxy}{path_depth};
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

  # E-mail transport.
  if ($conf->{mail}{from}) {
    if ($conf->{smtp}{hosts}) {
      my $c = $conf->{smtp};
      my %args = map {$_ => $c->{$_}} keys %$c;
      my @hosts = split(' ', $c->{hosts});
      $args{hosts} = \@hosts;
      $self->{mailtransport} = Email::Sender::Transport::SMTP->new(%args);
    }
    else {
      $self->{mailtransport} = Email::Sender::Transport::Sendmail->new(
        $conf->{sendmail}
      );
    }
  }
}

1;
