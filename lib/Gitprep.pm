use 5.008007;
package Gitprep;
use Mojo::Base 'Mojolicious';

use Carp 'croak';
use DBIx::Custom;
use Gitprep::API;
use Gitprep::Git;
use Gitprep::Manager;
use Scalar::Util 'weaken';
use Validator::Custom;

# Digest::SHA loading to Mojo::Util if not loaded
{
  package Mojo::Util;
  eval {require Digest::SHA; import Digest::SHA qw(sha1 sha1_hex)};
}

our $VERSION = 'v1.6';

has 'dbi';
has 'git';
has 'manager';
has 'vc';

use constant BUFFER_SIZE => 8192;

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
  
  # Git
  my $git = Gitprep::Git->new;
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
  
  # Encoding suspects list for Git
  my $encoding_suspects
    = $conf->{basic}{encoding_suspects} ||= 'utf8';
  $encoding_suspects = [split /,/, $encoding_suspects] unless ref $encoding_suspects eq 'ARRAY';
  $git->encoding_suspects($encoding_suspects);

  # Repository Manager
  my $manager = Gitprep::Manager->new(app => $self);
  weaken $manager->{app};
  $self->manager($manager);
  
  # Repository home
  my $rep_home = $ENV{GITPREP_REP_HOME} || $self->home->rel_file('data/rep');
  $git->rep_home($rep_home);
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
  my $db_file = $ENV{GITPREP_DB_FILE}
    || $self->home->rel_file('data/gitprep.db');
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
  
  # Setup database
  $self->manager->setup_database;
  
  # Model
  my $models = [
    {table => 'user', primary_key => 'id'},
    {table => 'project', primary_key => ['user_id', 'name']},
    {table => 'number', primary_key => 'key'},
    {table => 'collaboration', primary_key => ['user_id', 'project_name', 'collaborator_id']}
  ];
  $dbi->create_model($_) for @$models;

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
      
      return ($value || '') =~ /^[a-zA-Z0-9_\-][a-zA-Z0-9_\-\.]*$/;
    }
  );
  
  # Basic auth plugin
  $self->plugin('BasicAuth');

  # Routes
  sub template {
    my $template = shift;
    
    return sub { shift->render($template, , 'mojo.maybe' => 1) };
  }
  
  {
    my $r = $self->routes;

    # DBViewer(only development)
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
        my $id_re = qr/[a-zA-Z0-9_-]+/;
        
        # User
        my $r = $r->route('/:user', user => $id_re);
        {
          # Home
          $r->get('/' => template '/user');
          
          # Settings
          $r->get('/_settings' => template '/user-settings');
        }

        # Smart HTTP
        {
          
          my $r = $r->route('/(:project).git', project => $id_re);
          
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
            $r->get('/info/refs' => template 'smart-http/info-refs');
            
            # /git-upload-pack or /git-receive-pack
            $r->any('/git-(:service)'
              => [service => qr/(?:upload-pack|receive-pack)/]
              => template 'smart-http/service'
            );
            
            # Static file
            $r->get('/(*Path)' => template 'smart-http/static');
          }
        }
                
        # Project
        {
          my $r = $r->route('/:project', project => $id_re);
          
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
            $r->get('/' => template '/project');
            
            # Commit
            $r->get('/commit/*diff' => template '/commit');
            
            # Commits
            $r->get('/commits/*rev_file' => template '/commits');
            
            # Branches
            $r->any('/branches/*base_branch' => {base_branch => undef} => template '/branches');

            # Tags
            $r->get('/tags' => template '/tags');

            # Tree
            $r->get('/tree/*rev_dir' => template '/tree');
            
            # Blob
            $r->get('/blob/*rev_file' => template '/blob');
            
            # Sub module
            $r->get('/submodule/*rev_file' => template '/submodule');

            # Raw
            $r->get('/raw/*rev_file' => template '/raw');

            # Blame
            $r->get('/blame/*rev_file' => template '/blame');
            
            # Archive
            $r->get('/archive/(*rev).tar.gz' => template '/archive')->to(archive_type => 'tar');
            $r->get('/archive/(*rev).zip' => template '/archive')->to(archive_type => 'zip' );
            
            # Compare
            $r->get('/compare/(*rev1)...(*rev2)' => template '/compare');
            
            # Settings
            $r->any('/settings' => template '/settings');
            
            # Collaboration
            $r->any('/settings/collaboration' => template '/settings/collaboration');
            
            # Fork
            $r->any('/fork' => template '/fork');

            # Network
            $r->get('/network' => template '/network');

            # Network Graph
            $r->get('/network/graph/(*rev1)...(*rev2_abs)' => template '/network/graph');

            # Import branch
            $r->any('/import-branch/:remote_user/:remote_project' => template '/import-branch');
            
            # Get branches and tags
            $r->get('/api/revs' => template '/api/revs');
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
