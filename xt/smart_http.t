use Test::More 'no_plan';
use strict;
use warnings;

use FindBin;
use utf8;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";
use File::Path 'rmtree';
use Encode qw/encode decode/;
use MIME::Base64 'encode_base64';

use Test::Mojo;

# Test DB
my $db_file = $ENV{GITPREP_DB_FILE} = "$FindBin::Bin/smart_http.db";

# Test Repository home
my $rep_home = $ENV{GITPREP_REP_HOME} = "$FindBin::Bin/smart_http";

$ENV{GITPREP_NO_MYCONFIG} = 1;

use Gitprep;

note 'Smart HTTP';
{
  unlink $db_file;
  rmtree $rep_home;

  my $app = Gitprep->new;
  $app->manager->setup_database;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'});
  $t->content_like(qr/Login page/);

  # Login success
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'a'});
  $t->content_like(qr/Admin/);
  
  # Create user
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto', password => 'a', password2 => 'a'});
  $t->content_like(qr/Success.*created/);

  # Login as kimoto
  $t->post_ok('/_login?op=login', form => {id => 'kimoto', password => 'a'});
  $t->get_ok('/')->content_like(qr/kimoto/);

  # Create repository
  $t->post_ok('/_new?op=create', form => {project => 't1', description => 'Hello', readme => 1});
  $t->content_like(qr/README/);
  
  # info/refs
  $t->get_ok("/kimoto/t1.git/info/refs");
  $t->status_is(200);
  $t->content_type_is('text/plain; charset=UTF-8');
  
  my $object_id1 = substr($t->tx->res->body, 0, 2);
  my $object_id2 = substr($t->tx->res->body, 2, 38);
  
  # Loose object
  $t->get_ok("/kimoto/t1.git/objects/$object_id1/$object_id2");
  $t->status_is(200);
  $t->content_type_is('application/x-git-loose-object');

  # /info/pack
  $t->get_ok('/kimoto/t1.git/objects/info/packs');
  $t->status_is(200);
  $t->content_type_is('text/plain; charset=UTF-8');

  # /HEAD
  $t->get_ok('/kimoto/t1.git/HEAD');
  $t->status_is(200);
  $t->content_type_is('text/plain');
  $t->content_like(qr#ref: refs/heads/master#);
  
  # /info/refs upload-pack request
  $t->get_ok('/kimoto/t1.git/info/refs?service=git-upload-pack');
  $t->status_is(200);
  $t->header_is('Content-Type', 'application/x-git-upload-pack-advertisement');
  $t->content_like(qr/^001e# service=git-upload-pack/);
  $t->content_like(qr/multi_ack_detailed/);
  
  # /info/refs recieve-pack request(Basic authentication)
  $t->get_ok('/kimoto/t1.git/info/refs?service=git-receive-pack');
  $t->status_is(401);
  
  # /info/refs recieve-pack request
  $t->get_ok(
    '/kimoto/t1.git/info/refs?service=git-receive-pack',
    {
      Authorization => 'Basic ' . encode_base64('kimoto:a')
    }
  );
  $t->header_is("Content-Type", "application/x-git-receive-pack-advertisement");
  $t->content_like(qr/^001f# service=git-receive-pack/);
  $t->content_like(qr/report-status/);
  $t->content_like(qr/delete-refs/);
  $t->content_like(qr/ofs-delta/);
  
  # /git-receive-pack
  $t->post_ok(
    '/kimoto/t1.git/git-receive-pack',
    {
      'Content-Type' => 'application/x-git-receive-pack-request',
      Content => '00810000000000000000000000000000000000000000 6410316f2ed260666a8a6b9a223ad3c95d7abaed refs/tags/v1.0. report-status side-band-64k0000'
    }
  );
  $t->status_is(200);
  $t->content_type_is('application/x-git-receive-pack-result');

  # /git-upload-pack
  {
    my $content = <<EOS;
006fwant 6410316f2ed260666a8a6b9a223ad3c95d7abaed multi_ack_detailed no-done side-band-64k thin-pack ofs-delta
0032want 6410316f2ed260666a8a6b9a223ad3c95d7abaed
00000009done
EOS
    $t->post_ok(
      '/kimoto/t1.git/git-upload-pack',
      {
        'Content-Type' => 'application/x-git-upload-pack-request',
        'Content-Length' => 174,
        'Content'        => $content
      }
    );
    $t->status_is(200);
    $t->content_type_is('application/x-git-upload-pack-result');
  }
}

note 'Private repository and collaborator';
{
  unlink $db_file;
  rmtree $rep_home;

  my $app = Gitprep->new;
  $app->manager->setup_database;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'});
  $t->content_like(qr/Login page/);

  # Login success
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'a'});
  $t->content_like(qr/Admin/);
  
  # Create user
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto', password => 'a', password2 => 'a'});
  $t->content_like(qr/Success.*created/);
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto2', password => 'a', password2 => 'a'});
  $t->content_like(qr/Success.*created/);

  # Login as kimoto
  $t->post_ok('/_login?op=login', form => {id => 'kimoto', password => 'a'});
  $t->get_ok('/')->content_like(qr/kimoto/);

  # Create repository
  $t->post_ok('/_new?op=create', form => {project => 't1', description => 'Hello', readme => 1});
  $t->content_like(qr/README/);
  
  # Check private repository
  $t->post_ok("/kimoto/t1/settings?op=save-settings", form => {private => 1});
  $t->content_like(qr/Settings is saved/);
  
  # Can access private repository from myself
  $t->get_ok(
    '/kimoto/t1.git/info/refs?service=git-receive-pack',
    {
      Authorization => 'Basic ' . encode_base64('kimoto:a')
    }
  );
  $t->header_is("Content-Type", "application/x-git-receive-pack-advertisement");
  $t->content_like(qr/^001f# service=git-receive-pack/);
  
  # Can't access private repository from others
  $t->get_ok(
    '/kimoto/t1.git/info/refs?service=git-receive-pack',
    {
      Authorization => 'Basic ' . encode_base64('kimoto2:a')
    }
  );
  $t->status_is(401);

  # Add collaborator
  $t->post_ok("/kimoto/t1/settings/collaboration?op=add", form => {collaborator => 'kimoto2'});
  $t->content_like(qr/Collaborator kimoto2 is added/);
  
  # Can access private repository from collaborator
  $t->get_ok(
    '/kimoto/t1.git/info/refs?service=git-receive-pack',
    {
      Authorization => 'Basic ' . encode_base64('kimoto2:a')
    }
  );
  $t->header_is("Content-Type", "application/x-git-receive-pack-advertisement");
  $t->content_like(qr/^001f# service=git-receive-pack/);
}

# Fix test error(why?)
__END__
