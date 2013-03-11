use 5.008007;
package Gitprep;

our $VERSION = '0.01';

use Mojo::Base 'Mojolicious';
use Gitprep::Git;
use DBIx::Custom;
use Validator::Custom;
use Encode qw/encode decode/;
use Mojo::JSON;

has 'git';
has 'dbi';
has 'validator';

sub startup {
  my $self = shift;
  
  # Config
  my $conf_file = $ENV{GITPREP_CONFIG_FILE}
    || $self->home->rel_file('gitprep.conf');
  $self->plugin('JSONConfigLoose', {file => $conf_file}) if -f $conf_file;
  my $conf = $self->config;
  $conf->{search_dirs} ||= ['/git/pub', '/home'];
  $conf->{search_max_depth} ||= 10;
  $conf->{logo_link} ||= "https://github.com/yuki-kimoto/gitprep";
  $conf->{hypnotoad} ||= {listen => ["http://*:10010"]};
  $conf->{prevent_xss} ||= 0;
  $conf->{encoding} ||= 'UTF-8';
  $conf->{text_exts} ||= ['txt'];
  $conf->{root} ||= '/gitprep';
  $conf->{ssh_port} ||= '';
  
  # Added public directory
  push @{$self->static->paths}, $conf->{root};
  
  # Git
  my $git = Gitprep::Git->new;
  my $git_bin = $conf->{git_bin} ? $conf->{git_bin} : $git->search_bin;
  die qq/Can't detect git command. set "git_bin" in gitprep.conf/
    unless $git_bin;
  $git->bin($git_bin);
  $git->search_dirs($conf->{search_dirs});
  $git->search_max_depth($conf->{search_max_depth});
  $git->encoding($conf->{encoding});
  $git->text_exts($conf->{text_exts});
  $self->git($git);

  # Reverse proxy support
  $ENV{MOJO_REVERSE_PROXY} = 1;
  $self->hook('before_dispatch' => sub {
    my $self = shift;
    
    if ( $self->req->headers->header('X-Forwarded-Host')) {
        my $prefix = shift @{$self->req->url->path->parts};
        push @{$self->req->url->base->path->parts}, $prefix;
    }
  });
  
  # Route
  my $r = $self->routes->route->to('main#');

  # Home
  $r->get('/')->to('#home');
  
  # Start
  $r->any('/_start')->to('#start');
  
  # Sign in
  $r->any('/_login')->to('#login');
  
  # Admin
  $r->get('/_admin')->to('#admin');
  
  # Admin
  {
    my $r = $r->route('/_admin')->to('admin#');
    
    # Create new repository
    $r->get('/create')->to('#create');
    
    # User
    $r->any('/user')->to('#user');
  }

  # User
  $r->get('/:user')->to('#user');
  
  # Project
  {
    my $r = $r->route('/:user/:project');
    $r->get('/')->to('#project');
    
    # Commit
    $r->get('/commit/#diff')->to('#commit');
    
    # Commits
    $r->get('/commits/#rev', {id => 'HEAD'})->to('#commits');
    $r->get('/commits/#rev/(*blob)')->to('#commits');
    
    # Branches
    $r->get('/branches')->to('#branches');

    # Tags
    $r->get('/tags')->to('#tags');

    # Tree
    $r->get('/tree/(*object)')->to('#tree');
    
    # Blob
    $r->get('/blob/(*object)')->to('#blob');
    
    # Blob diff
    $r->get('/blobdiff/(#diff)/(*file)')->to('#blobdiff');
    
    # Raw
    $r->get('/raw/(*object)')->to('#raw');
    
    # Archive
    $r->get('/archive/(#rev).tar.gz')->to('#archive', archive_type => 'tar');
    $r->get('/archive/(#rev).zip')->to('#archive', archive_type => 'zip');
    
    # Compare
    $r->get('/compare/(#rev1)...(#rev2)')->to('#compare');
  }
  
  # File cache
  $git->search_projects;
  
  # DBI
  my $db_file = $self->home->rel_file('db/gitprep.db');
  my $dbi = DBIx::Custom->connect(
    dsn => "dbi:SQLite:database=$db_file",
    connector => 1,
    option => {sqlite_unicode => 1}
  );

  eval {
  # Create table
    my $sql = <<"EOS";
create table user (
  row_id integer primary key autoincrement,
  id not null unique,
  config not null
);
EOS
    $dbi->execute($sql);
  };
  $self->dbi($dbi);
  
  # Model
  $dbi->create_model({table => 'user', primary_key => 'id'});
  
  # Fiter
  $dbi->register_filter(json => sub {
    my $value = shift;
    
    if (ref $value) {
      return decode('UTF-8', Mojo::JSON->new->encode($value));
    }
    else {
      return Mojo::JSON->new->decode(encode('UTF-8', $value));
    }
  });
  
  # Validator
  my $validator = Validator::Custom->new;
  $self->validator($validator);
}

1;
