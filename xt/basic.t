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

diag 'Commit page - first commit';
{
  # Page access
  $t->get_ok("/$user/$project/commit/4b0e81c462088b16fefbe545e00b993fd7e6f884");
  
  # Commit message
  $t->content_like(qr/first commit/);
  
  # Parent not eixsts
  $t->content_like(qr/0 <span .*?>parent/);
  
  # Commit id
  $t->content_like(qr/4b0e81c462088b16fefbe545e00b993fd7e6f884/);
  
  # Author
  $t->content_like(qr/Yuki Kimoto/);
  
  # File change count
  $t->content_like(qr/1 changed files/);
  
  # Added README
  $t->content_like(qr/class="file-add".*?README/s);
  
  # Empty file is added
  $t->content_like(qr/No changes/);
}

diag 'Commits page';
{
  # Page access
  $t->get_ok("/$user/$project/commits/master");
  
  # Date
  $t->content_like(qr/\d{4}-\d{2}-\d{3}/);
}
