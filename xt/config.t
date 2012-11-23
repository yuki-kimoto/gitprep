use strict;
use warnings;
use utf8;

use Test::More 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../mojolegacy/lib";
use lib "$FindBin::Bin/../lib";
use Gitweblite;

$ENV{GITWEBLITE_CONFIG_FILE} = "$FindBin::Bin/test.conf";
my $app = Gitweblite->new;
my $conf = $app->config;
is($conf->{search_max_depth}, 15);
is($conf->{logo_link}, "https://github.com/yuki-kimoto/gitweblite");
