use 5.008007;
package Gitweblite;

our $VERSION = '1.00';

use Mojo::Base 'Mojolicious';
use Gitweblite::Git;

has 'git';

sub startup {
  my $self = shift;
  
  # Config
  my $conf_file = $ENV{GITWEBLITE_CONFIG_FILE}
    || $self->home->rel_file('gitweblite.conf');
  $self->plugin('JSONConfigLoose', {file => $conf_file}) if -f $conf_file;
  my $conf = $self->config;
  $conf->{search_dirs} ||= ['/git/pub', '/home'];
  $conf->{search_max_depth} ||= 10;
  $conf->{logo_link} ||= "https://github.com/yuki-kimoto/gitweblite";
  $conf->{hypnotoad} ||= {listen => ["http://*:10010"]};
  $conf->{prevent_xss} ||= 0;
  $conf->{encoding} ||= 'UTF-8';
  $conf->{text_exts} ||= ['txt'];
  
  # Git
  my $git = Gitweblite::Git->new;
  my $git_bin = $conf->{git_bin} ? $conf->{git_bin} : $git->search_bin;
  die qq/Can't detect git command. set "git_bin" in gitweblite.conf/
    unless $git_bin;
  $git->bin($git_bin);
  $git->search_dirs($conf->{search_dirs});
  $git->search_max_depth($conf->{search_max_depth});
  $git->encoding($conf->{encoding});
  $git->text_exts($conf->{text_exts});
  $self->git($git);

  # Helper
  {
    # Remove top slash
    $self->helper('gitweblite_rel' => sub {
      my ($self, $path) = @_;
      
      $path =~ s/^\///;
      
      return $path;
    });
    
    # Get head commit id
    $self->helper('gitweblite_get_head_id' => sub {
      my ($self, $project) = @_;
      
      my $head_commit = $self->app->git->parse_commit($project, "HEAD");
      my $head_id = $head_commit->{id};
      
      return $head_id;
    });
  }
  
  # Added user public and templates path
  unshift @{$self->static->paths}, $self->home->rel_file('user/public');
  unshift @{$self->renderer->paths}, $self->home->rel_file('user/templates');
  
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
  
  # Projects
  $r->get('/(*home)/projects')->to('#projects')->name('projects');
  
  # Project
  {
    my $r = $r->route('/(*project)', project => qr/.+?\.git/);
    
    # Summary
    $r->get('/summary')->to('#summary')->name('summary');
    
    # Short log
    $r->get('/shortlog/(*id)', {id => 'HEAD'})
      ->to('#log', short => 1)->name('shortlog');
    
    # Log
    $r->get('/log/(*id)', {id => 'HEAD'})->to('#log')->name('log');
    
    # Commit
    $r->get('/commit/(*id)')->to('#commit')->name('commit');
    
    # Commit diff
    $r->get('/commitdiff/(*diff)')->to('#commitdiff')->name('commitdiff');
    
    # Commit diff plain
    $r->get('/commitdiff-plain/(*diff)')
      ->to('#commitdiff', plain => 1)->name('commitdiff_plain');
    
    # Tags
    $r->get('/tags')->to('#tags')->name('tags');
    
    # Tag
    $r->get('/tag/(*id)')->to('#tag')->name('tag');
    
    # Heads
    $r->get('/heads')->to('#heads')->name('heads');
    
    # Tree
    $r->get('/tree/(*id_dir)', {id_dir => 'HEAD'})
      ->to('#tree')->name('tree');
    
    # Blob
    $r->get('/blob/(*id_file)')->to('#blob')->name('blob');
    
    # Blob plain
    $r->get('/blob-plain/(*id_file)')
      ->to('#blob', plain => 1)->name('blob_plain');
    
    # Blob diff
    $r->get('/blobdiff/(#diff)/(*file)')
      ->to('#blobdiff')->name('blobdiff');

    # Blob diff plain
    $r->get('/blobdiff-plain/(#diff)/(*file)')
      ->to('#blobdiff', plain => 1)->name('blobdiff_plain');
    
    # Snapshot
    $r->get('/snapshot/(:id)', {id => 'HEAD'})
      ->to('#snapshot')->name('snapshot');
  }
  
  # File cache
  $git->search_projects;
}

1;
