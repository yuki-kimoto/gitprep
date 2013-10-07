use Test::More 'no_plan';
use strict;
use warnings;

use FindBin;
use utf8;
use lib "$FindBin::Bin/../mojo/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";
use File::Path 'rmtree';
use Encode qw/encode decode/;

use Test::Mojo;

# Test DB
my $db_file = $ENV{GITPREP_DB_FILE} = "$FindBin::Bin/smart_http.db";

# Test Repository home
my $rep_home = $ENV{GITPREP_REP_HOME} = "$FindBin::Bin/smart_http";

$ENV{GITPREP_NO_MYCONFIG} = 1;

use Gitprep;

# For perl 5.8
{
  no warnings 'redefine';
  sub note { print STDERR "# $_[0]\n" unless $ENV{HARNESS_ACTIVE} }
}

note 'Smart HTTP';
{
  unlink $db_file;
  rmtree $rep_home;

  my $app = Gitprep->new;
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

=pod
  # Loose object
  $t->get_ok("/kimoto/t1.git/objects/20/42336f878dd054083193909140d1d10c16e775");
  $t->status_is(200);
  $t->content_type_is('application/x-git-loose-object');
=cut

  
  
}
