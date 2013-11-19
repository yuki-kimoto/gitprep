use Test::More 'no_plan';

use FindBin;
use utf8;
use lib "$FindBin::Bin/../mojo/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";
use Encode qw/encode decode/;

use Test::Mojo;

# Test DB
$ENV{GITPREP_DB_FILE} = "$FindBin::Bin/basic_enc.db";

# Test Repository home
$ENV{GITPREP_REP_HOME} = "$FindBin::Bin/../../gitprep_t_rep_home";

$ENV{GITPREP_NO_MYCONFIG} = 1;

use Gitprep;

my $app = Gitprep->new;
my $t = Test::Mojo->new($app);

my $user = 'kimoto';
my $project = 'gitprep_t';

# For perl 5.8
{
  no warnings 'redefine';
  sub note { print STDERR "# $_[0]\n" unless $ENV{HARNESS_ACTIVE} }
}

# Encoding(EUC-jp)
$t->get_ok("/$user/$project/blob/ed7b91659762fa612563f0595f3faca6aecfcfa0/euc-jp.txt");
$t->content_like(qr/あああ/);
