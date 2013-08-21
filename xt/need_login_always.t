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

$ENV{GITPREP_NO_MYCONFIG} = 1;


use Gitprep;

# For perl 5.8
{
  no warnings 'redefine';
  sub note { print STDERR "# $_[0]\n" unless $ENV{HARNESS_ACTIVE} }
}

note 'Start page';
{
  unlink $db_file;
  rmtree $rep_home;
  
  my $app = Gitprep->new;
  my $t = Test::Mojo->new($app);
  $t->ua->max_redirects(3);
  
  $app->config->{basic}{need_login_always} = 1;
  $app->config->{basic}{reset_password} = 1;
  
  # Access start page
  $t->get_ok('/_start');
  $t->content_like(qr/Start page/);

  # Create admin user
  $t->post_ok('/_start?op=create', form => {password => 'a', password2 => 'a'});
  $t->content_like(qr/Login page/);

  # Login as admin
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'a'});

  # Create user
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto1', password => 'a', password2 => 'a'});
  $t->content_like(qr/kimoto1/);

  # Access reset password page
  $t->get_ok('/reset-password');
  $t->content_like(qr/Reset password page/);
  
  # Access login page
  $t->get_ok('/_login');
  $t->content_like(qr/Login page/);
  
  # Logout
  $t->get_ok('/_logout');
  
  # Redirect to login page from other page
  $t->get_ok('/_new');
  $t->content_like(qr/Login page/);
}
