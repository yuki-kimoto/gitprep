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

$ENV{GITPREP_TEST} = 1;

# Test DB
my $db_file = $ENV{GITPREP_DB_FILE} = "$FindBin::Bin/user.db";

# Test Repository home
my $rep_home = $ENV{GITPREP_REP_HOME} = "$FindBin::Bin/user";

use Gitprep;


note 'Start page';
{
  unlink $db_file;

  my $app = Gitprep->new;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Redirect to _start page
  $t->get_ok('/');
  $t->content_like(qr/Create Admin User/);

  # Page access
  $t->get_ok('/_start');
  $t->content_like(qr/Create Admin User/);
  
  # Password is empty
  $t->post_ok('/_start?op=create', form => {password => ''});
  $t->content_like(qr/Password is empty/);
  
  # Password contains invalid character
  $t->post_ok('/_start?op=create', form => {password => "\t"});
  $t->content_like(qr/Password contains invalid character/);

  # Password contains invalid character
  $t->post_ok('/_start?op=create', form => {password => 'a' x 21});
  $t->content_like(qr/Password is too long/);

  # Two password don't match
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'b'});
  $t->content_like(qr/Two password/);
  
  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'});
  $t->content_like(qr/Login Page/);

  # Admin user already exists
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'});
  $t->content_like(qr/Admin user already exists/);
}

note 'Admin pages';
{
  unlink $db_file;

  my $app = Gitprep->new;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'});
  $t->content_like(qr/Login Page/);
  
  # Page access
  $t->get_ok('/_login');
  $t->content_like(qr/Login Page/);
  
  # Login fail
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'b'});
  $t->content_like(qr/User name or password is wrong/);

  # Login success
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'a'});
  $t->content_like(qr/Admin/);
  
  note 'Admin page';
  {
    $t->post_ok('/_admin');
    $t->content_like(qr/Admin/);
  }
  
  note 'Admin User page';
  {
    $t->get_ok('/_admin/users');
    $t->content_like(qr/Admin Users/);
  }

  note 'Create User page';
  {
    # Page access
    $t->get_ok('/_admin/user/create');
    $t->content_like(qr/Create User/);
    
    # User name is empty
    $t->post_ok('/_admin/user/create?op=create', form => {id => ''});
    $t->content_like(qr/User name is empty/);

    # User name contain invalid character
    $t->post_ok('/_admin/user/create?op=create', form => {id => '&'});
    $t->content_like(qr/User name contain invalid character/);

    # User name is too long
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a' x 21});
    $t->content_like(qr/User name is too long/);

    # Password is empty
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a', password => ''});
    $t->content_like(qr/Password is empty/);

    # Password contain invalid character
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a', password => "\t"});
    $t->content_like(qr/Password contain invalid character/);

    # Password contain invalid character
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a', password => 'a' x 21});
    $t->content_like(qr/Password is too long/);

    # Password contain invalid character
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'a', password => 'a', password2 => 'b'});
    $t->content_like(qr/Two password/);
    
    # Create user
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto', password => 'a', password2 => 'a'});
    $t->content_like(qr/Success.*created/);
  }
    
  note 'Admin Users page';
  $t->get_ok('/_admin/users');
  $t->content_like(qr/Admin Users/);
  $t->content_like(qr/kimoto/);
  
  note 'Reset password page';
  {
    # Page access
    $t->get_ok('/reset-password?user=kimoto');
    $t->content_like(qr/Reset Password/);
    $t->content_like(qr/kimoto/);
    
    # Password is empty
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => ''});
    $t->content_like(qr/Password is empty/);

    # Password contains invalid character
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => "\t"});
    $t->content_like(qr/Password contains invalid character/);

    # Password is too long
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => 'a' x 21});
    $t->content_like(qr/Password is too long/);
    
    # Two password don't match
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => 'a', password2 => 'b'});
    $t->content_like(qr/Two password/);

    # Reset password
    $t->post_ok('/reset-password?user=kimoto&op=reset', form => {password => 'a', password2 => 'a'});
    $t->content_like(qr/Success.*changed/);
  }

  note 'Delete user';
  {
    # Create user
    $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto-tmp', password => 'a', password2 => 'a'});
    $t->content_like(qr/kimoto-tmp/);
    $t->get_ok('/_admin/users');
    $t->content_like(qr/kimoto-tmp/);

    # User not exists
    $t->post_ok('/_admin/users?op=delete', form => {user => 'kimoto-notting'});
    $t->content_like(qr/Internal/);

    # User not exists
    $t->post_ok('/_admin/users?op=delete', form => {user => 'kimoto-tmp'});
    $t->content_like(qr/User.*deleted/);
    $t->get_ok('/_admin/users');
    $t->content_unlike(qr/kimoto-tmp/);
  }
  
  note 'logout';
  $t->get_ok('/_logout');
  $t->get_ok('/_admin');
  $t->content_like(qr/Users/);
}

note 'Reset password';
{
  unlink $db_file;

  my $app = Gitprep->new;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);

  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'});
  $t->content_like(qr/Login Page/);;

  # Not loing user can't access
  $t->get_ok('/reset-password');
  $t->content_like(qr/Users/);

  # Cnahge password(reset_password conf on)
  $app->config->{admin}{reset_password} = 1;
  $t->get_ok('/reset-password');
  $t->content_like(qr/Reset Password/);
  $t->post_ok('/reset-password?op=reset', form => {password => 'b', password2 => 'b'});
  $t->content_like(qr/Success.*changed/);
  $app->config->{admin}{reset_password} = 0;

  # Login success
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'b'});
  $t->content_like(qr/Admin/);
  
  # Create user
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto1', password => 'a', password2 => 'a'});
  $t->content_like(qr/kimoto1/);
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto2', password => 'a', password2 => 'a'});
  $t->content_like(qr/kimoto2/);
  
  # Logout
  $t->get_ok('/_logout');
  
  # Login as kimoto
  $t->post_ok('/_login?op=login', form => {id => 'kimoto1', password => 'a'});
  $t->get_ok('/')->content_like(qr/kimoto1/);

  # Don't change other user password
  $t->get_ok('/reset-password?user=kimoto2');
  $t->content_like(qr/Users/);
  $t->post_ok('/reset-password?user=kimoto2&op=reset', form => {password => 'b', password2 => 'b'});
  $t->content_like(qr/Users/);

  # Reset password
  $t->get_ok('/reset-password?user=kimoto1');
  $t->content_like(qr/Reset Password/);
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
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'});
  $t->content_like(qr/Login Page/);

  # Login as admin
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'a'});

  # Create user
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto1', password => 'a', password2 => 'a'});
  $t->content_like(qr/kimoto1/);
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto2', password => 'a', password2 => 'a'});
  $t->content_like(qr/kimoto2/);
  
  # Login as kimoto1
  $t->post_ok('/_login?op=login', form => {id => 'kimoto1', password => 'a'});

  # User account settings
  $t->get_ok('/kimoto1/_settings');
  $t->content_like(qr/User Account Settings/);
  
  # Other user can't access
  $t->get_ok('/kimoto2/_settings');
  $t->content_like(qr/Users/);
  
  note 'Create repository';
  {
    # Create repository page
    $t->get_ok('/_new');
    $t->content_like(qr/Create repository/);
    
    # Not logined user can't access
    $t->get_ok('/_logout');
    $t->get_ok('/_new');
    $t->content_like(qr/Users/);
    $t->post_ok('/_login?op=login', form => {id => 'kimoto1', password => 'a'});
    
    # Create repository
    $t->post_ok('/_new?op=create', form => {project => 't1', description => 'Hello'});
    $t->content_like(qr/Create a new repository on the command line/);
    $t->content_like(qr/t1\.git/);
    $t->content_like(qr/Hello/);

    # Create repository(with readme)
    $t->post_ok('/_new?op=create', form => {project => 't2', description => 'Hello', readme => 1});
    $t->content_like(qr/first commit/);
    $t->content_like(qr/t2\.git/);
    $t->content_like(qr/README/);

    # Settings page(don't has README)
    $t->get_ok('/kimoto1/t1/settings');
    $t->content_like(qr/Settings/);

    # Settings page(has README)
    $t->get_ok('/kimoto1/t2/settings');
    $t->content_like(qr/Settings/);
  }
  
  note 'Project settings';
  {
    note 'Rename project';
    {
      # Empty
      $t->post_ok('/kimoto1/t2/settings?op=rename-project', form => {});
      $t->content_like(qr/Repository name is empty/);
      
      # Invalid character
      $t->post_ok('/kimoto1/t2/settings?op=rename-project', form => {'to-project' => '&'});
      $t->content_like(qr/Repository name contains invalid charactor/);
      
      # Rename project
      $t->post_ok('/kimoto1/t2/settings?op=rename-project', form => {'to-project' => 't3'});
      $t->content_like(qr/Repository name is renamed to t3/);
      $t->post_ok('/kimoto1/t3/settings?op=rename-project', form => {'to-project' => 't2'});
      $t->content_like(qr/Repository name is renamed to t2/);
    }
    
    note 'Change description';
    {
      # Change description
      $t->post_ok("/kimoto1/t1/settings?op=change-description", form => {description => 'あああ'});
      $t->content_like(qr/Description is saved/);
      $t->content_like(qr/あああ/);
    }
    
    note 'Change default branch';
    {
      # Default branch default
      $t->get_ok('/kimoto1/t1/settings');
      $t->content_like(qr/master/);
      
      # Change default branch
      my $cmd = "git --git-dir=$rep_home/kimoto1/t2.git branch b1";
      system($cmd) == 0 or die "Can't execute git branch";
      $t->get_ok('/kimoto1/t2/settings');
      $t->content_like(qr/b1/);
      $t->post_ok("/kimoto1/t2/settings?op=default-branch", form => {'default-branch' => 'b1'});
      $t->content_like(qr/Default branch is changed to b1/);
    }
  }
}
