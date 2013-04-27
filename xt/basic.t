use Test::More 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../mojo/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";

use Test::Mojo;
use Gitprep;

my $app = Gitprep->new;
my $t = Test::Mojo->new($app);

my $user = 'kimoto';
my $project = 'gitprep_t';

# First commit
subtest 'first commit' => sub {
  $t->get_ok("/$user/$project/commit/4b0e81c462088b16fefbe545e00b993fd7e6f884");
};

