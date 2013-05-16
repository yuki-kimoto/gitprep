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


note '_start page';
{
  unlink $db_file;

  my $app = Gitprep->new;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Redirect to _start page
  $t->get_ok('/')->content_like(qr/Create Admin User/);

  # Page access
  $t->get_ok('/_start')->content_like(qr/Create Admin User/);
  
  # Password is empty
  $t->post_ok('/_start?op=create', form => {password => ''})
    ->content_like(qr/Password is empty/)
  ;
  
  # Password contains invalid character
  $t->post_ok('/_start?op=create', form => {password => "\t"})
    ->content_like(qr/Password contains invalid character/)
  ;

  # Password contains invalid character
  $t->post_ok('/_start?op=create', form => {password => 'a' x 21})
    ->content_like(qr/Password is too long/)
  ;

  # Two password don't match
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'b'})
    ->content_like(qr/Two password/)
  ;
  
  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'})
    ->content_like(qr/Login Page/);
  ;

  # Admin user already exists
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'})
    ->content_like(qr/Admin user already exists/);
  ;

}
