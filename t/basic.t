use Test::More 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../mojo/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";

use Test::Mojo;

use_ok('Gitprep');
