use Test::More 'no_plan';

use FindBin;
use utf8;
use lib "$FindBin::Bin/../mojo/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";
use Encode qw/encode decode/;

use Test::Mojo;

$ENV{GITPREP_TEST} = 1;

# Test DB
my $db_file = $ENV{GITPREP_DB_FILE} = "$FindBin::Bin/admin.db";

# Test Repository home
my $rep_home = $ENV{GITPREP_REP_HOME} = "$FindBin::Bin/admin";

use Gitprep;

my $app = Gitprep->new;
my $t = Test::Mojo->new($app);
$t->ua->max_redirects(3);

note '_start page';
{
  # Redirect to _start page
  $t->get_ok('/')->content_like(qr/Create Admin User/);

  # Page access
  $t->get_ok('/_start')->content_like(qr/Create Admin User/);
  
  # Password is empty
  $t->post_ok('/_start?op=create', form => {password => ''})
    ->content_like(qr/Password is empty/)
  ;
}
