use Test::More 'no_plan';
use strict;
use warnings;

use FindBin;
use utf8;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";
use File::Path 'rmtree';
use Encode qw/encode decode/;

use Test::Mojo;

# Test DB
my $db_file = $ENV{GITPREP_DB_FILE} = "$FindBin::Bin/import_rep/gitprep.db";

# Test Repository home
my $rep_home = $ENV{GITPREP_REP_HOME} = "$FindBin::Bin/import_rep/rep";

$ENV{GITPREP_NO_MYCONFIG} = 1;

use Gitprep;

note 'import_rep';
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

  # Login as admin
  $t->post_ok('/_login?op=login', form => {id => 'admin', password => 'a'});
  $t->content_like(qr/Admin/);

  # Create user
  $t->post_ok('/_admin/user/create?op=create', form => {id => 'kimoto', mail => 'kimoto@foo.com', password => 'a', password2 => 'a'});
  $t->content_like(qr/Success.*created/);
  
  # Import repositories
  my $rep_dir = "$FindBin::Bin/../../gitprep_t_rep_home/kimoto";
  chdir "$FindBin::Bin/../script"
    or die "Can't change directory: $!";
  my @cmd = ('./import_rep', '-u', 'kimoto', $rep_dir);
  system(@cmd) == 0
    or die "Command fail: @cmd";
  
  # Branch
  ok(-f "$rep_home/kimoto/gitprep_t.git/refs/heads/b1");

  # Tag
  ok(-f "$rep_home/kimoto/gitprep_t.git/refs/tags/t1");
  
  # Description
  ok(-f "$rep_home/kimoto/gitprep_t.git/description");
}

