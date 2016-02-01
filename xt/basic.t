use Test::More 'no_plan';

use FindBin;
use utf8;
use lib "$FindBin::Bin/../mojo/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../extlib/lib/perl5";
use Encode qw/encode decode/;

use Test::Mojo;

# Test DB
$ENV{GITPREP_DB_FILE} = "$FindBin::Bin/basic.db";

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
  
  # Commit datetime
  $t->content_like(qr/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
  
  # README
  $t->content_like(qr/README/);
  
  # tree directory link
  $t->content_like(qr#/$user/$project/tree/master/dir#);

  # tree file link
  $t->content_like(qr#/$user/$project/blob/master/README#);
}

note 'Commit page';
{
  note 'first commit';
  {
    # Page access
    $t->get_ok("/$user/$project/commit/4b0e81c462088b16fefbe545e00b993fd7e6f884");
    
    # Commit message
    $t->content_like(qr/first commit/);
    
    # Commit datetime
    $t->content_like(qr/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
    
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
    $t->content_like(qr/class="file-add"/);
  }
  
  note 'rename';
  {
    $t->get_ok("/$user/$project/commit/15ea9d711617abda5eed7b4173a3349d30bca959");
    $t->content_like(qr#1 <span class="muted">parent</span>.*1b59896#s);
    $t->content_like(qr/File renamed without changes/);
    $t->content_like(qr/a.txt → a_renamed.txt/);
    $t->content_like(qr/class="file-renamed"/);
  }
  
  note 'add text';
  {
    $t->get_ok("/$user/$project/commit/da5b854b760351adc58d24d121070e729e80534d");
    $t->content_like(qr/\@\@/);
    $t->content_like(qr/\+aaa/);
  }
  
  note 'added aaa to a_renamed.txt for merge commit';
  {
    $t->get_ok("/$user/$project/commit/da5b854b760351adc58d24d121070e729e80534d");
    $t->content_like(qr/\@\@/);
  }
  
  note 'add image data';
  {
    $t->get_ok("/$user/$project/commit/0b6eca6a28538b1226961ca7655d2662f3522652");
    $t->content_like(qr/BIN/);
    $t->content_like(qr#/raw/0b6eca6a28538b1226961ca7655d2662f3522652/sample.png#);
  }
  
  note 'binary data';
  {
    $t->get_ok("/$user/$project/commit/ed7b91659762fa612563f0595f3faca6aecfcfa0");
    $t->content_like(qr/Binary file not shown/);
  }
  
  note 'binary data rename';
  {
    $t->get_ok("/$user/$project/commit/3c617100f8e6d8ffe11d6c14ddf7b3646a198269");
    $t->content_like(qr/File renamed without changes/);
  }
  
  note 'Branch name';
  {
    # Page access (branch name)
    $t->get_ok("/$user/$project/commit/b1");
    $t->content_like(qr/\+bbb/);

    # Page access (branch name long)
    $t->get_ok("/$user/$project/commit/refs/heads/b1");
    $t->content_like(qr/\+bbb/);
    $t->content_like(qr#refs/heads/b1#);
  }
  
  note 'Branch and tag refernce';
  {
    $t->get_ok("/$user/$project/commit/6d71d9bc1ee3bd1c96a559109244c1fe745045de");
    $t->content_like(qr/b2/);
    $t->content_like(qr/t21/);
    $t->content_unlike(qr/t21\^\{\}/);
  }
  
}

note 'Commits page';
{
  {
    # Page access
    $t->get_ok("/$user/$project/commits/master");
    $t->content_like(qr/Commit History/);
    
    # Commit date time
    $t->content_like(qr/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
  }
  {
    # Page access(branch name long)
    $t->get_ok("/$user/$project/commits/refs/heads/master");
    $t->content_like(qr#refs/heads/master#);
  }
  
  # Commits page - atom feed
  {
    # Page access(branch name long)
    $t->get_ok("/$user/$project/commits/master.atom");
    $t->content_like(qr/\Q<?xml version="1.0" encoding="UTF-8" ?>/);
    $t->content_like(qr/<entry>/);
  }
}

note 'History page';
{
  {
    # Page access
    $t->get_ok("/$user/$project/commits/b1/README");
    $t->content_like(qr/Commits on/);
    
    # Content
    $t->content_like(qr/first commit/);
  }
  {
    # Page access (branch name long)
    $t->get_ok("/$user/$project/commits/refs/heads/b1/README");
    
    # Content
    $t->content_like(qr/first commit/);
  }
}

note 'Tags page';
{
  # Page access
  $t->get_ok("/$user/$project/tags?page=2");
  
  # Commit datetime
  $t->content_like(qr/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
  
  # Tree link
  $t->content_like(qr#/$user/$project/tree/t1#);
  
  # Commit link
  $t->content_like(qr#/$user/$project/commit/15ea9d711617abda5eed7b4173a3349d30bca959#);

  # Zip link
  $t->content_like(qr#/$user/$project/archive/t1.zip#);
  
  # Tar.gz link
  $t->content_like(qr#/$user/$project/archive/t1.tar.gz#);
}

note 'Tree page';
{
  {
    # Page access (hash)
    $t->get_ok("/$user/$project/tree/e891266d8aeab864c8eb36b7115416710b2cdc2e");
    
    # Commit datetime
    $t->content_like(qr/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
    
    # README
    $t->content_like(qr/README.*bbb/s);
    
    # tree directory link
    $t->content_like(qr#/$user/$project/tree/e891266d8aeab864c8eb36b7115416710b2cdc2e/dir#);

    # tree file link
    $t->content_like(qr#/$user/$project/blob/e891266d8aeab864c8eb36b7115416710b2cdc2e/README#);
  }
  {
    # Page access (branch name)
    $t->get_ok("/$user/$project/tree/b21/dir");
    
    # File
    $t->content_like(qr/b\.txt/s);
  }
  {
    # Page access (branch name middle)
    $t->get_ok("/$user/$project/tree/heads/b21/dir");
    
    # File
    $t->content_like(qr/dir\/b\.txt/s);
  }
  {
    # Page access (branch name long)
    $t->get_ok("/$user/$project/tree/refs/heads/b21/dir");
    $t->content_like(qr#refs/heads/b21#);
    
    # File
    $t->content_like(qr/b\.txt/s);
  }
}

note 'Blob page';
{
  {
    # Page access (hash)
    $t->get_ok("/$user/$project/blob/b9f0f107672b910a44d22d4623ce7445d40565aa/a_renamed.txt");
    
    # Commit datetime
    $t->content_like(qr/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/);
    
    # Content
    $t->content_like(qr/あああ/);
  }
  {
    # Page access (branch name)
    $t->get_ok("/$user/$project/blob/b1/README");
    
    # Content
    $t->content_like(qr/bbb/);
  }
  {
    # Page access (branch name middle)
    $t->get_ok("/$user/$project/blob/heads/b1/README");
    
    # Content
    $t->content_like(qr/bbb/);
  }
  {
    # Page access (branch name long)
    $t->get_ok("/$user/$project/blob/refs/heads/b1/README");
    $t->content_like(qr#refs/heads/b1#);
    
    # Content
    $t->content_like(qr/bbb/);
  }
  
  note 'blob binary';
  {
    $t->get_ok("/$user/$project/blob/ed7b91659762fa612563f0595f3faca6aecfcfa0/sample.bin");
    $t->content_like(qr/View raw/);
  }
}

note 'raw page';
{
  {
    # Page access (hash)
    $t->get_ok("/$user/$project/raw/b9f0f107672b910a44d22d4623ce7445d40565aa/a_renamed.txt");
    
    # Content
    my $content_binary = $t->tx->res->body;
    my $content = decode('UTF-8', $content_binary);
    like($content, qr/あああ/);
  }
  {
    # Page access (branch name)
    $t->get_ok("/$user/$project/raw/b21/dir/b.txt");
    
    my $content = $t->tx->res->body;
    like($content, qr/aaaa/);
  }
  {
    # Page access (branch name middle)
    $t->get_ok("/$user/$project/raw/heads/b21/dir/b.txt");
    
    my $content = $t->tx->res->body;
    like($content, qr/aaaa/);
  }
  {
    # Page access (branch name long)
    $t->get_ok("/$user/$project/raw/refs/heads/b21/dir/b.txt");
    
    my $content = $t->tx->res->body;
    like($content, qr/aaaa/);
  }
}

note 'Aarchive';
{
  # Archive zip
  $t->get_ok("/$user/$project/archive/t1.zip");
  $t->content_type_is('application/zip');
  
  # Archice tar.gz
  $t->get_ok("/$user/$project/archive/t1.tar.gz");
  $t->content_type_is('application/x-tar');
}

note 'Compare page';
{
  # Page access (branch name)
  $t->get_ok("/$user/$project/compare/b1...master");
  $t->content_like(qr#renamed dir/a\.txt to dir/b\.txt and added text#);

  # Page access (branch name long)
  $t->get_ok("/$user/$project/compare/refs/heads/b1...refs/heads/master");
  $t->content_like(qr#renamed dir/a\.txt to dir/b\.txt and added text#);

}

note 'API References';
{
  # Page access (branch name)
  $t->get_ok("/$user/$project/api/revs");
  my $content = $t->tx->res->body;
  like($content, qr/branch_names/);
  like($content, qr/tag_names/);
}

note 'Network page';
{
  # Page access
  $t->get_ok("/$user/$project/network");
  $t->content_like(qr/Network/);
}

note 'README';
{
  # Links
  $t->get_ok("/$user/$project/tree/84199670c2f8e51f87b05b336020bde968975498");
  $t->content_like(qr#<a href="http://foo1">http://foo1</a>#);
  $t->content_like(qr#<a href="https://foo2">https://foo2</a>#);
  $t->content_like(qr#<a href="http://foo3">http://foo3</a>#);
  $t->content_like(qr#<a href="http://foo4">http://foo4</a>#);
  $t->content_like(qr#<a href="http://foo5">http://foo5</a>#);
}

note 'Branches';
{
  # Page access
  $t->get_ok("/$user/$project/branches");
  $t->content_like(qr/Branches/);
  
}

note 'Compare';
{
  # Page access
  $t->get_ok("/$user/$project/compare/master...no_merged");
  $t->content_like(qr/branch change/);
  $t->content_like(qr#http://foo5branch change#);
}

note 'blame';
{
  # Page access
  $t->get_ok("/$user/$project/blame/3c617100f8e6d8ffe11d6c14ddf7b3646a198269/README");
  $t->content_like(qr/Blame page/);
  
  # Commit link
  $t->content_like(qr#/commit/0929b1a4ee79d0f104fd9ef7d6d410d501a273cf#);
  
  # Lines
  $t->content_like(qr#http://foo1#);
}

note 'Markdown normal file';
{
  # Page access
  $t->get_ok("/$user/$project/blob/12e44f2e4ecf55c5d3a307889829b47c05e216d3/dir/markdown.md");
  $t->content_like(qr#<h1 .*?>Head</h1>#);
}

note 'encoding_suspects option';
{
  my $app = Gitprep->new;
  $app->git->encoding_suspects(['EUC-jp', 'UTF-8']);
  my $t = Test::Mojo->new($app);
  $t->get_ok("/$user/$project/blob/3cf14ade5e28ee0cd83b9a3b1e1c332aed66df53/euc-jp.txt");
  $t->content_like(qr/あああ/);
}
