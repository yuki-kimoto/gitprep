use Test::More 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../mojo/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";

use Test::Mojo;

# Test DB
$ENV{GITPREP_DB_FILE} = "$FindBin::Bin/basic.db";

# Test Repository home
$ENV{GITPREP_REP_HOME} = "$FindBin::Bin/../../gitprep_t_rep_home";

use Gitprep;

my $app = Gitprep->new;
my $t = Test::Mojo->new($app);

my $user = 'kimoto';
my $project = 'gitprep_t';

note 'Home page';
{
  # Page access
  $t->get_ok('/');
  
  # Title
  $t->content_like(qr/GitPrep/);
  $t->content_like(qr/Users/);
  
  # User link
  $t->content_like(qr#/$user#);
}

note 'Projects page';
{
  # Page access
  $t->get_ok("/$user");
  
  # Title
  $t->content_like(qr/Repositories/);
  
  # project link
  $t->content_like(qr#/$user/$project#);
}

note 'Project page';
{
  # Page access
  $t->get_ok("/$user/$project");
  
  # Description
  $t->content_like(qr/gitprep test repository/);
  
  # README
  $t->content_like(qr/README/);
  
  # tree directory link
  $t->content_like(qr#/$user/$project/tree/master/dir#);

  # tree file link
  $t->content_like(qr#/$user/$project/blob/master/README#);
}

note 'Commit page - first commit';
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

note 'Commits page';
{
  # Page access
  $t->get_ok("/$user/$project/commits/master");
  
  # Date
  $t->content_like(qr/\d{4}-\d{2}-\d{2}/);
}

note 'Tags page';
{
  # Page access
  $t->get_ok("/$user/$project/tags");
  
  # Tree link
  $t->content_like(qr#/$user/$project/tree/t1#);
  
  # Commit link
  $t->content_like(qr#/$user/$project/commit/15ea9d711617abda5eed7b4173a3349d30bca959#);

  # Zip link
  $t->content_like(qr#/$user/$project/archive/t1.zip#);
  
  # Tar.gz link
  $t->content_like(qr#/$user/$project/archive/t1.tar.gz#);
}
