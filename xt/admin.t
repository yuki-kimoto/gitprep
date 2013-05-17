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


note 'Start page';
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

note 'Login as admin user';
{
  unlink $db_file;

  my $app = Gitprep->new;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'})
    ->content_like(qr/Login Page/);
  ;
  
  # Page access
  $t->get_ok('/_login')->content_like(qr/Login Page/);
  
  # Login fail
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'b'})
    ->content_like(qr/User name or password is wrong/)
  ;

  # Login success
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'a'})
    ->content_like(qr/Admin/)
  ;
  
  note 'Admin page';
  {
    $t->post_ok('/_admin')->content_like(qr/Admin/);
  }
  
  note 'Admin User page';
  {
    $t->post_ok('/_admin/users')->content_like(qr/Admin Users/);
  }

  note 'Create User page';
  {
    # Page access
    $t->get_ok('/_admin/user/create')->content_like(qr/Create User/);
    
    # User name is empty
    $t->post_ok('/_admin/user/create?op=create', form => {id => ''})
      ->content_like(qr/User name is empty/);

    # User name contain invalid character
    $t->post_ok('/_admin/user/create?op=create', form => {id => '&'})
      ->content_like(qr/User name contain invalid character/);

    # User name is too long
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a' x 21})
      ->content_like(qr/User name is too long/);

    # Password is empty
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a', password => ''})
      ->content_like(qr/Password is empty/);

    # Password contain invalid character
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a', password => "\t"})
      ->content_like(qr/Password contain invalid character/);

    # Password contain invalid character
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a', password => 'a' x 21})
      ->content_like(qr/Password is too long/);

    # Password contain invalid character
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a', password => 'a', password2 => 'b'})
      ->content_like(qr/Two password/);
    
    # Create user
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto', password => 'a', password2 => 'a'})
      ->content_like(qr/Success.*created/);
    
    # Admin Users page
    $t->get_ok('/_admin/users')
      ->content_like(qr/Admin Users/)
      ->content_like(qr/kimoto/);
  }
}
