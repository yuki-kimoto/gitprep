use 5.008007;
package Gitprep;

use Mojo::Base 'Mojolicious';
use Gitprep::Git;
use DBIx::Custom;
use Validator::Custom;
use Encode qw/encode decode/;
use Gitprep::API;
use Carp 'croak';
use Gitprep::Manager;
use Scalar::Util 'weaken';
use Carp 'croak';

our $VERSION = '0.04';

has 'git';
has 'dbi';
has 'validator';
has 'manager';

sub startup {
  my $self = shift;
  
  # Config file
  $self->plugin('INIConfig', {ext => 'conf'});
  
  # Config file for developper
  my $my_conf_file = $self->home->rel_file('gitprep.my.conf');
  $self->plugin('INIConfig', {file => $my_conf_file}) if -f $my_conf_file;
  
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
  $self->git($git);
  
  # Added public path
  push @{$self->static->paths}, $rep_home;
  
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
    {table => 'number', primary_key => 'key'}
  ];
  $dbi->create_model($_) for @$models;

  # Validator
  my $validator = Validator::Custom->new;
  $self->validator($validator);
  $validator->register_constraint(
    user_name => sub {
      my $value = shift;
      
      return ($value || '') =~ /^[a-zA-Z0-9_\-]+$/
    },
    project_name => sub {
      my $value = shift;
      
      return ($value || '') =~ /^[a-zA-Z0-9_\-]+$/
    }
  );
  
  # Helper
  {
    # API
    $self->helper(gitprep_api => sub { Gitprep::API->new(shift) });
    
    # Finish rendering
    $self->helper(finish_rendering => sub {
      my $self = shift;
      
      $self->stash->{'mojo.routed'} = 1;
      $self->rendered;
      
      return $self;
    });
  }
  
  # Routes
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
        
        # Admin page authentication
        {
          my $path = $self->req->url->path->parts->[0] || '';

          if ($path eq '_admin' && !$api->logined_admin) {
            $self->redirect_to('/');
            return;
          }
        }
        
        return 1; 
      });
      $self->plugin('AutoRoute', route => $r);
    }

    # Custom routes
    {
      # User
      my $r = $r->route('/:user');
      {
        # Home
        $r->get('/')->name('user');
        
        # Settings
        $r->get('/_settings')->name('user-settings');
      }
      
      # Project
      {
        my $r = $r->route('/:project');
        
        # Home
        $r->get('/')->name('project');
        
        # Commit
        $r->get('/commit/*diff')->name('commit');
        
        # Commits
        $r->get('/commits/*rev_file', {file => undef})->name('commits');
        
        # Branches
        $r->any('/branches/*base_branch', {base_branch => undef})->name('branches');

        # Tags
        $r->get('/tags');

        # Tree
        $r->get('/tree/*rev_dir', {dir => undef})->name('tree');
        
        # Blob
        $r->get('/blob/*rev_file', {file => undef})->name('blob');
        
        # Raw
        $r->get('/raw/*rev_file', {file => undef})->name('raw');
        
        # Archive
        $r->get('/archive/(*rev).tar.gz')->to(archive_type => 'tar')->name('archive');
        $r->get('/archive/(*rev).zip')->to(archive_type => 'zip')->name('archive');
        
        # Compare
        $r->get('/compare/(*rev1)...(*rev2)')->name('compare');
        
        # Settings
        $r->any('/settings');
        
        # Fork
        $r->any('/fork');

        # Network
        $r->get('/network');

        # Network Graph
        $r->get('/network/graph/(*rev1)...(*rev2_abs)')->name('network/graph');
        
        # Get branches and tags
        $r->get('/api/revs')->name('api/revs');
      }
    }
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
}

1;
