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
  
  
}
