use strict;
use warnings;
use utf8;

use Test::More;

plan skip_all => 'require Archive::Tar'
  unless eval { require Archive::Tar; 1 };

use File::Temp 'tempdir';
require Archive::Tar;

plan 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../mojolegacy/lib";
use lib "$FindBin::Bin/../lib";
use Gitweblite;

use Test::Mojo;

my $app = Gitweblite->new;
my $t = Test::Mojo->new($app);

my $home = '/home/kimoto/labo';
my $project = "$home/gitweblite_devrep.git";

# Snapshot
{
  my $id = 'a37fbb832ab530fe9747cb128f9461211959103b';
  $t->get_ok("$project/snapshot/$id");
  my $tmpdir = tempdir(CLEANUP => 1);
  my $tmpfile = "$tmpdir/snapshot.tar.gz";
  $t->tx->res->content->asset->move_to($tmpfile);
  my $at = Archive::Tar->new($tmpfile);
  
  ok($at->contains_file('gitweblite_devrep-a37fbb8/README'));
  ok($at->contains_file('gitweblite_devrep-a37fbb8/dir/a.txt'));
}
