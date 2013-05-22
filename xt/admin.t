use Test::More 'no_plan';

use FindBin;
use utf8;
use lib "$FindBin::Bin/../mojo/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";
use File::Path 'rmtree';
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

note 'Admin pages';
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
    $t->get_ok('/_admin/users')->content_like(qr/Admin Users/);
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
  }
    
  note 'Admin Users page';
  $t->get_ok('/_admin/users')
    ->content_like(qr/Admin Users/)
    ->content_like(qr/kimoto/);
  
  note 'Reset password page';
  {
    # Page access
    $t->get_ok('/reset-password?user=kimoto')
      ->content_like(qr/Reset Password/)
      ->content_like(qr/kimoto/)
    ;
    
    # Password is empty
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => ''})
      ->content_like(qr/Password is empty/)
    ;

    # Password contains invalid character
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => "\t"})
      ->content_like(qr/Password contains invalid character/)
    ;

    # Password is too long
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => 'a' x 21})
      ->content_like(qr/Password is too long/)
    ;
    
    # Two password don't match
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => 'a', password2 => 'b'})
      ->content_like(qr/Two password/)
    ;

    # Reset password
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => 'a', password2 => 'a'})
      ->content_like(qr/Success.*changed/)
    ;
  }

  note 'Delete user';
  {
    # Create user
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto-tmp', password => 'a', password2 => 'a'})
      ->content_like(qr/kimoto-tmp/);
    $t->get_ok('/_admin/users')
      ->content_like(qr/kimoto-tmp/);

    # User not exists
    $t->post_ok('/_admin/users?op=delete', form => {user => 'kimoto-notting'})
      ->content_like(qr/Internal/);

    # User not exists
    $t->post_ok('/_admin/users?op=delete', form => {user => 'kimoto-tmp'})
      ->content_like(qr/User.*deleted/);
    $t->get_ok('/_admin/users')
      ->content_unlike(qr/kimoto-tmp/);

    ;
  }
  
  note 'logout';
  $t->get_ok('/_logout')
    ->get_ok('/_admin')
    ->content_like(qr/Users/);
}

note 'Reset password';
{
  unlink $db_file;

  my $app = Gitprep->new;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'})
    ->content_like(qr/Login Page/);
  ;

  # Not loing user can't access
  $t->get_ok('/reset-password')
    ->content_like(qr/Users/);

  # Cnahge password(reset_password conf on)
  $app->config->{admin}{reset_password} = 1;
  $t->get_ok('/reset-password')
    ->content_like(qr/Reset Password/);
  $t->post_ok('/reset-password?op=reset', form => {password => 'b', password2 => 'b'})
    ->content_like(qr/Success.*changed/)
  ;
  $app->config->{admin}{reset_password} = 0;

  # Login success
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'b'})
    ->content_like(qr/Admin/)
  ;
  
  # Create user
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto1', password => 'a', password2 => 'a'})
    ->content_like(qr/kimoto1/);
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto2', password => 'a', password2 => 'a'})
    ->content_like(qr/kimoto2/);
  
  # Logout
  $t->get_ok('/_logout');
  
  # Login as kimoto
  $t->post_ok('/_login?op=login', form => {id => 'kimoto1', password => 'a'});
  $t->get_ok('/')->content_like(qr/kimoto1/);

  # Don't change other user password
  $t->get_ok('/reset-password?user=kimoto2')
    ->content_like(qr/Users/)
  ;
  $t->post_ok('/reset-password?user=kimoto2&op=reset', form => {password => 'b', password2 => 'b'})
    ->content_like(qr/Users/)
  ;

  # Reset password
  $t->get_ok('/reset-password?user=kimoto1')
    ->content_like(qr/Reset Password/)
  ;
  $t->post_ok('/reset-password?user=kimoto1&op=reset', form => {password => 'b', password2 => 'b'});
  
  # Login as kimoto
  $t->get_ok('/_logout');
  $t->post_ok('/_login?op=login', form => {id => 'kimoto1', password => 'b'});
  $t->get_ok('/')->content_like(qr/kimoto1/);
}

note 'User Account Settings';
{
  unlink $db_file;
  rmtree $rep_home;

  my $app = Gitprep->new;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'})
    ->content_like(qr/Login Page/);
  ;

  # Login as admin
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'a'});

  # Create user
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto1', password => 'a', password2 => 'a'})
    ->content_like(qr/kimoto1/);
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto2', password => 'a', password2 => 'a'})
    ->content_like(qr/kimoto2/);
  
  # Login as kimoto1
  $t->post_ok('/_login?op=login', form => {id => 'kimoto1', password => 'a'});

  # User account settings
  $t->get_ok('/kimoto1/_settings')
    ->content_like(qr/User Account Settings/)
  ;
  
  # Other user can't access
  $t->get_ok('/kimoto2/_settings')
    ->content_like(qr/Users/)
  ;
  
  note 'Create repository';
  {
    # Create repository page
    $t->get_ok('/_new')
      ->content_like(qr/Create repository/)
    ;
    
    # Not logined user can't access
    $t->get_ok('/_logout');
    $t->get_ok('/_new')
      ->content_like(qr/Users/)
    ;
    $t->post_ok('/_login?op=login', form => {id => 'kimoto1', password => 'a'});
    
    # Create repository
    $t->post_ok('/_new?op=create', form => {project => 't1', description => 'Hello'})
      ->content_like(qr/Create a new repository on the command line/)
      ->content_like(qr/t1\.git/)
      ->content_like(qr/Hello/)
    ;

    # Create repository(with readme)
    $t->post_ok('/_new?op=create', form => {project => 't2', description => 'Hello', readme => 1})
      ->content_like(qr/first commit/)
      ->content_like(qr/t2\.git/)
      ->content_like(qr/README/)
    ;
    
    # Settings page(don't has README)
    $t->get_ok('/kimoto1/t1/settings')
      ->content_like(qr/Settings/)
    ;
    
    # Settings page(has README)
    $t->get_ok('/kimoto1/t2/settings')
      ->content_like(qr/Settings/)
    ;
  }
}


