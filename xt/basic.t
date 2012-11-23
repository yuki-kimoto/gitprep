use strict;
use warnings;
use utf8;
use File::Temp 'tempdir';

use Test::More 'no_plan';

use FindBin;
use lib "$FindBin::Bin/../mojolegacy/lib";
use lib "$FindBin::Bin/../lib";
use Gitweblite;

use Test::Mojo;

my $app = Gitweblite->new;
my $t = Test::Mojo->new($app);

# Home page
$t->get_ok('/')
  ->content_like(qr/Gitweb Lite/)
  ->content_like(qr/Home Directory/)
  ->content_like(qr#/home/kimoto/labo/#)
  ->content_like(qr#href="/home/kimoto/labo/projects"#)
;

# Projects page
my $home = '/home/kimoto/labo';
$t->get_ok("$home/projects")
  # Page title
  ->content_like(qr/Projects/)
  # Home directory
  ->content_like(qr#<a href="/">home</a> &gt;\s*<a href="/home/kimoto/labo/projects">/home/kimoto/labo</a>#)
  # Project link
  ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/summary">\s+gitweblite_devrep.git\s+</a>#)
  # Description link
  ->content_like(qr#<a class="list" title="Test Repository テストリポジトリ\s*"\s*href="/home/kimoto/labo/gitweblite_devrep.git/summary">\s*Test Repository テストリポジトリ\s*</a>#)
  # Owner
  ->content_like(qr#<td><i>kimoto</i></td>#)
  # Content links
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/summary">summary</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog">shortlog</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log">log</a>#)
  ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree">#)
;

# Summary page
my $project = "$home/gitweblite_devrep.git";
my $git = $app->git;
{
  my $head = $git->head_id($project);
  my $commit = $git->parse_commit($project, 'HEAD');
  my $title_short = $commit->{title_short};
  my $tag_t21 = $git->tag($project, 't21');
  $t->get_ok("$project/summary")
    # Page navi
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/$head">Shortlog</a>#)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log/$head">Log</a>#)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$head">\s*Commit\s*</a>#)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff/$head">Commitdiff</a>#)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$head">Tree</a>#)
    # Description
    ->content_like(qr#<tr id="metadata_desc"><td><b>Description:</b></td><td>Test Repository テストリポジトリ\s*</td></tr>#)
    # Owner
    ->content_like(qr#<tr id="metadata_owner"><td><b>Owner:</b></td><td>kimoto</td></tr>#)
    # Ripository URL
    ->content_like(qr#http://somerep.git\s*<br />\s*git://somerep.git\s*<br />#)
    # Branch
    ->content_like(qr#<span class="head" title="heads/master">\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/heads/master">\s*master\s*</a>\s*</span>#)
    # Shortlog title link
    ->content_like(qr#<a class="title" href="/home/kimoto/labo/gitweblite_devrep.git/shortlog">\s*Shortlog\s*</a>#)
    # Shorlog comment link
    ->content_like(qr#<a class="list subject"\s*href="/home/kimoto/labo/gitweblite_devrep.git/commit/$head">\s*$title_short\s*</a>#)
    # Shortlog commit link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$head">\s*commit\s*</a>#)
    # Shortlog commitdiff link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff/$head">\s*commitdiff\s*</a>#)
    # Shortlog tree link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$head">\s*tree\s*</a>#)
    # Shortlog snapshot link
    ->content_like(qr#<a title="in format: tar.gz" rel="nofollow" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/snapshot/$head">\s*snapshot\s*</a>#)
    # Shortlog page ... link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog">\s*\.\.\.\s*</a>#)
    # Tag name link
    ->content_like(qr#<a class="list name"\s*href="/home/kimoto/labo/gitweblite_devrep.git/commit/$tag_t21->{refid}"\s*>\s*t10\s*</a>#)
    # Tag comment link
    ->content_like(qr#<a class="list subject"\s*href="/home/kimoto/labo/gitweblite_devrep.git/tag/$tag_t21->{id}"\s*>\s*t21\s*</a>#)
    # Tag shortlog link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/tags/t21"\s*>\s*shortlog\s*</a>#)  # Tag log link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/tags/t21">\s*log\s*</a>#)
    # Tags link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tags">\s*...\s*</a>#)

    # Head name link
    ->content_like(qr#<a class="list name"\s*href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/heads/b10">\s*b10\s*</a>#)
    # Head shortlog link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/heads/b10">\s*shortlog\s*</a>#)
    # Head log link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/heads/b10">\s*log\s*</a>#)
    # Head tree link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/b10">\s*tree\s*</a>#)
    # Heads link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/heads">\s*...\s*</a>#)
  ;
}

# Commit page
{
  my $id = '6d71d9bc1ee3bd1c96a559109244c1fe745045de';
  my $commit = $git->parse_commit($project, $id);
  my $parent = $commit->{parent};
  my $parent_short = substr($parent, 0, 7);
  $t->get_ok("$project/commit/$id")
    # Parent
    ->content_like(qr#parent:\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent">\s*$parent_short\s*</a>#)
    # Title
    ->content_like(qr#<a class="title" href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff/$id">\s*日本語の内容を追加\s*</a>#)
    # Head link
    ->content_like(qr#<span class="head" title="heads/b10">\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/heads/b10">\s*b10\s*</a>\s*</span>#)
    # Tag link
    ->content_like(qr#<span class="tag" title="tags/t10">\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/tags/t10">\s*t10\s*</a>\s*</span>#)
    # Author
    ->content_like(qr#<td>author</td>\s*<td>Yuki Kimoto &lt;kimoto.yuki\@gmail.com&gt;</td>#)
    # Committer
    ->content_like(qr#<td>committer</td>\s*<td>Yuki Kimoto &lt;kimoto.yuki\@gmail.com&gt;</td>#)
    # Commit
    ->content_like(qr#<td>commit</td>\s*<td class="sha1">$id</td>#)
    # Tree commit id link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$id">\s*tree\s*</a>#)
    # Tree link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$id">\s*tree\s*</a>#)
    # Snapshot link
    ->content_like(qr#<a title="in format: tar.gz" rel="nofollow"\s*href="/home/kimoto/labo/gitweblite_devrep.git/snapshot/$id">\s*snapshot\s*</a>#)
    # Parent commit id link
    ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent">\s*$parent\s*</a>#)
    # Parent commit link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent">\s*commit\s*</a>#)
    # Comment
    ->content_like(qr#<div class="page_body">\s*日本語の内容を追加<br/>\s*<br/>\s*</div>#)
    # Commit difftree file name link
    ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/blob/$id/a_renamed.txt">\s*a_renamed.txt\s*</a>#)
    # Commit difftree blobdiff link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blobdiff/$parent\.\.$id/a_renamed.txt">\s*diff\s*</a>#)
    # Commit difftree blob link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/$id/a_renamed.txt">\s*blob\s*</a>#)
  ;
}

# Commit page (Merge commit)
{
  my $id = '495195e5a9eec6c0126df9017c320f9dc2e5d0ef';
  my $commit = $git->parse_commit($project, $id);
  my $parent1 = $commit->{parents}->[0];
  my $parent1_short = substr($parent1, 0, 7);
  my $parent2 = $commit->{parents}->[1];
  my $parent2_short = substr($parent2, 0, 7);
  $t->get_ok("$project/commit/$id")
    # Merge parents
    ->content_like(qr#merge:\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent1">\s*$parent1_short</a>\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent2">\s*$parent2_short\s*</a>#)
    # Parent1
    ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent1">\s*$parent1\s*</a>#)
    # Parent2
    ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/commit/$parent2">\s*$parent2\s*</a>#)
    # Difftree Diff1
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blobdiff/$parent1\.\.$id/conflict.txt">\s*diff1\s*</a>#)
    # Defftree Diff2
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blobdiff/$parent2\.\.$id/conflict.txt">\s*diff2\s*</a>#)
  ;
}

# Commit page (First commit)
{
  my $id = '4b0e81c462088b16fefbe545e00b993fd7e6f884';
  $t->get_ok("$project/commit/$id")
    # Initial
    ->content_like(qr#\Q(initial)#)
    # New file
    ->content_like(qr#<span class="file_status new">\s*\[\s*new file\s*with mode: 0644\s*\]\s*</span>#)
  ;
}

# Commit page (Rename)
{
  my $id = '15ea9d711617abda5eed7b4173a3349d30bca959';
  my $commit = $git->parse_commit($project, $id);
  my $parent = $commit->{parent};
  $t->get_ok("$project/commit/$id")
    # Rename
    ->content_like(qr#\[\s*moved from\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/$parent/a\.txt">\s*a\.txt</a>\s*with 100%\s*\]#)
  ;
}

# Commit page (Change mode)
{
  my $id = '5a4043069b01c2a0c257dae1cc862c730bdb2c2f';
  my $commit = $git->parse_commit($project, $id);
  my $parent = $commit->{parent};
  $t->get_ok("$project/commit/$id")
    # Change mode
    ->content_like(qr#\[\s*changed\s*mode: 0644->0755\s*\]#)
  ;
}

# Blob page
{
  my $id = '68a698012b16490e8cfb9d66bf8bbd9085421c69';
  my $file = 'dir/a.txt';
  $t->get_ok("$project/blob/$id/$file")
    # Raw link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blob-plain/$id/$file">\s*Raw\s*</a>#)
    # HEAD link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/HEAD/dir/a.txt">\s*HEAD\s*</a>#)
    # Page path(project)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/$id">gitweblite_devrep.git</a>#)
    # Page path(blob)
    ->content_like(qr#<a title="tree home" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/tree/$id/dir"\s*>\s*dir\s*</a>\s*/\s*<a title="tree home" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/blob/$id/dir/a.txt">\s*a.txt\s*</a>#)
    # Content
    ->content_like(qr#<div class="pre"><a id="l1" href="1" class="linenr">   1</a> aaaa</div>#)
  ;
}

# Blob (tab)
{
  my $id = '26ab87d6c2640bde3807870347ea793cdf544a5c';
  my $file = 'tab.txt';
  $t->get_ok("$project/blob/$id/$file")
    # Content
    ->content_like(qr#1</a>   aaaaa#)
  ;
}

# Blob plain
{
  my $id = '68a698012b16490e8cfb9d66bf8bbd9085421c69';
  my $file = 'dir/a.txt';
  $t->get_ok("$project/blob-plain/$id/$file")
    # Content
    ->content_like(qr#aaaa#)
  ;
}

# Blob diff page
{
  my $id = '68a698012b16490e8cfb9d66bf8bbd9085421c69';
  my $from_id = 'a37fbb832ab530fe9747cb128f9461211959103b';
  my $file = 'dir/a.txt';
  $t->get_ok("$project/blobdiff/$from_id..$id/$file")
    # Raw link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blobdiff-plain/a37fbb832ab530fe9747cb128f9461211959103b..68a698012b16490e8cfb9d66bf8bbd9085421c69/dir/a.txt">\s*Raw\s*</a>#)
    # Page path (project)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/68a698012b16490e8cfb9d66bf8bbd9085421c69">gitweblite_devrep.git</a>#)
    # Page path (blob)
    ->content_like(qr#<a title="tree home" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/tree/68a698012b16490e8cfb9d66bf8bbd9085421c69/dir"\s*>\s*dir\s*</a>\s*/\s*<a title="tree home" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/blob/68a698012b16490e8cfb9d66bf8bbd9085421c69/dir/a.txt">\s*a.txt\s*</a>#)
    # Content (diff header)
    ->content_like(qr#<div class="diff header">diff --git\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/a37fbb832ab530fe9747cb128f9461211959103b/dir/a.txt">a/dir/a.txt</a>\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/68a698012b16490e8cfb9d66bf8bbd9085421c69/dir/a.txt">b/dir/a.txt</a></div>#)
    # Content (diff line)
    ->content_like(qr#<div class="diff to_file">\+aaaa</div>#)
  ;
}

# Blobdiff plain
{
  my $id = '68a698012b16490e8cfb9d66bf8bbd9085421c69';
  my $from_id = 'a37fbb832ab530fe9747cb128f9461211959103b';
  my $file = 'dir/a.txt';
  $t->get_ok("$project/blobdiff-plain/$from_id..$id/$file")
    # Content (diff line)
    ->content_like(qr#\+aaaa#)
  ;
}

# Tree page (Top direcotory)
{
  my $id = '68a698012b16490e8cfb9d66bf8bbd9085421c69';
  $t->get_ok("$project/tree/$id")
    # Snapshot link
    ->content_like(qr#<a title="in format: tar.gz" rel="nofollow"\s*href="/home/kimoto/labo/gitweblite_devrep.git/snapshot/$id">\s*snapshot\s*</a>#)
    # Commit comment
    ->content_like(qr#<a class="title" href="/home/kimoto/labo/gitweblite_devrep.git/commit/68a698012b16490e8cfb9d66bf8bbd9085421c69">\s*added text to dir/a.txt\s*</a>#)
    # File name link
    ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/blob/68a698012b16490e8cfb9d66bf8bbd9085421c69/README">\s*README\s*</a>#)
    # Blob link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/68a698012b16490e8cfb9d66bf8bbd9085421c69/README">\s*blob\s*</a>#)
    # Raw link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blob-plain/68a698012b16490e8cfb9d66bf8bbd9085421c69/README">\s*raw\s*</a>#)
    # Directory link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/68a698012b16490e8cfb9d66bf8bbd9085421c69/dir">\s*dir\s*</a>#)
    # Tree link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/68a698012b16490e8cfb9d66bf8bbd9085421c69/dir">\s*tree\s*</a>#)
  ;
}

# Tree page (Sub directory)
{
  my $id = '68a698012b16490e8cfb9d66bf8bbd9085421c69';
  my $dir = 'dir';
  $t->get_ok("$project/tree/$id/$dir")
    # Page path (project)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/68a698012b16490e8cfb9d66bf8bbd9085421c69">gitweblite_devrep.git</a>#)
    # Page path (directory)
    ->content_like(qr#<a title="tree home" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/tree/68a698012b16490e8cfb9d66bf8bbd9085421c69/dir">\s*dir\s*</a>#)
  ;
}

# Shortlog page (HEAD)
{
  $t->get_ok("$project/shortlog")
    # HEAD link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog">\s*HEAD\s*</a>#)
    # Next page link
    ->content_like(qr#<a title="Alt-n" accesskey="n" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/shortlog\?page=1">\s*Next\s*</a>#)
  ;
  $t->get_ok("$project/shortlog?page=1")
    # Prev page link
    ->content_like(qr#<a title="Alt-p" accesskey="p" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/shortlog\?page=0">\s*Prev\s*</a>#)
  ;
}

# Shortlog page (not HEAD)
{
  my $id = 'efcac846dfa843dca225c6d7445e349059011a44';
  $t->get_ok("$project/shortlog/$id")
    # Author
    ->content_like(qr#<td class="author">Yuki Kimoto</td>#)
    # Comment link
    ->content_like(qr#<a class="list subject" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/commit/efcac846dfa843dca225c6d7445e349059011a44">\s*edit a_renamed.txt\s*</a>#)
    # Commit link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/efcac846dfa843dca225c6d7445e349059011a44">commit</a>#)
    # Commitdiff link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff/efcac846dfa843dca225c6d7445e349059011a44">\s*commitdiff\s*</a>#)
    # Tree link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/efcac846dfa843dca225c6d7445e349059011a44">\s*tree\s*</a>#)
    # Snapshot link
    ->content_like(qr#<a title="in format: tar.gz" rel="nofollow" href=\s*/home/kimoto/labo/gitweblite_devrep.git/snapshot/efcac846dfa843dca225c6d7445e349059011a44>\s*snapshot\s*</a>#)
    
    ;
}

# Log page (HEAD)
{
  $t->get_ok("$project/log")
    # HEAD link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log">\s*HEAD\s*</a>#)
    # Next page link
    ->content_like(qr#<a title="Alt-n" accesskey="n" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/log\?page=1">\s*Next\s*</a>#)
  ;
  $t->get_ok("$project/log?page=1")
    # Prev page link
    ->content_like(qr#<a title="Alt-p" accesskey="p" href=\s*"/home/kimoto/labo/gitweblite_devrep.git/log\?page=0">\s*Prev\s*</a>#)
  ;
}

# Log page (not HEAD)
{
  my $id = 'efcac846dfa843dca225c6d7445e349059011a44';
  $t->get_ok("$project/log/$id")
    # Author
    ->content_like(qr#<span class="author_date">Yuki Kimoto#)
    # Comment link
    ->content_like(qr#edit a_renamed.txt#)
    # Commit link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/efcac846dfa843dca225c6d7445e349059011a44">commit</a>#)
    # Commitdiff link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff/efcac846dfa843dca225c6d7445e349059011a44">\s*commitdiff\s*</a>#)
    # Tree link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/efcac846dfa843dca225c6d7445e349059011a44">\s*tree\s*</a>#)
    ;
}

# Commitdiff page
{
  my $id = 'db9d83440469d42dda2021ebe34e20def0c0cba6';
  $t->get_ok("$project/commitdiff/$id")
    # Raw link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commitdiff-plain/db9d83440469d42dda2021ebe34e20def0c0cba6">\s*Raw\s*</a>#)
    # Comment link
    ->content_like(qr#<a class="title" href="/home/kimoto/labo/gitweblite_devrep.git/commit/">\s*edit a_renamed.txt\s*</a>#)
    # Author
    ->content_like(qr#<td>Author</td><td>Yuki Kimoto#)
    # Committer
    ->content_like(qr#<td>Committer</td><td>Yuki Kimoto#)
    # Difftree (file name link)
    ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/blob/db9d83440469d42dda2021ebe34e20def0c0cba6/a_renamed.txt">\s*a_renamed.txt\s*</a>#)
    # Difftree (diff link)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blobdiff/efcac846dfa843dca225c6d7445e349059011a44\.\.db9d83440469d42dda2021ebe34e20def0c0cba6/a_renamed.txt">\s*diff\s*</a>#)
    # Difftree (blob link)
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/db9d83440469d42dda2021ebe34e20def0c0cba6/a_renamed.txt">\s*blob\s*</a>#)
    # Content (diff header)
    ->content_like(qr#<div class="diff header">diff --git\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/efcac846dfa843dca225c6d7445e349059011a44/a_renamed.txt">a/a_renamed.txt</a>\s*<a href="/home/kimoto/labo/gitweblite_devrep.git/blob/db9d83440469d42dda2021ebe34e20def0c0cba6/a_renamed.txt">b/a_renamed.txt</a></div>#)
    # Content (added)
    ->content_like(qr#<div class="diff to_file">\+a</div>#)
}

# Commitdiff plain
{
  my $id = 'db9d83440469d42dda2021ebe34e20def0c0cba6';
  $t->get_ok("$project/commitdiff-plain/$id")
    # Content
    ->content_like(qr#\+a#)
}

# Tags page
{
  $t->get_ok("$project/tags")
    # Tag name link
    ->content_like(qr#<a class="list name"\s*href="/home/kimoto/labo/gitweblite_devrep.git/commit/6d71d9bc1ee3bd1c96a559109244c1fe745045de">\s*t21\s*</a>#)
    # Tag comment link
    ->content_like(qr#<a class="list subject"\s*href="/home/kimoto/labo/gitweblite_devrep.git/tag/38eaff4bf31775c7e32d5a62891e0e370e04d306">\s*t21\s*</a>#)
    # Tag link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tag/38eaff4bf31775c7e32d5a62891e0e370e04d306">\s*tag\s*</a>#)
    # Commot link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/6d71d9bc1ee3bd1c96a559109244c1fe745045de">\s*commit\s*</a>#)
    # Shotlog link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/tags/t21">\s*shortlog\s*</a>#)
    # Log
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/tags/t21">\s*log\s*</a>#)
  ;
}

# Tag page
{
  $t->get_ok("$project/tag/38eaff4bf31775c7e32d5a62891e0e370e04d306")
    # Object link
    ->content_like(qr#<a class="list" href="/home/kimoto/labo/gitweblite_devrep.git/commit/6d71d9bc1ee3bd1c96a559109244c1fe745045de">\s*6d71d9bc1ee3bd1c96a559109244c1fe745045de\s*</a>#)
    # Commit link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/commit/6d71d9bc1ee3bd1c96a559109244c1fe745045de">\s*commit\s*</a>#)
    # Author
    ->content_like(qr#<td>\s*author\s*</td>\s*<td>\s*Yuki Kimoto#)
    # Comment
    ->content_like(qr#<div class="page_body">\s*t21#)
}

# Heads page
{
  $t->get_ok("$project/heads")
    # Head name link
    ->content_like(qr#<a class="list name" href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/heads/master">\s*master\s*</a>#)
    # Shortlog link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/shortlog/refs/heads/master">\s*shortlog\s*</a>#)
    # Log link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/log/refs/heads/master">\s*log\s*</a>#)
    # Tree link
    ->content_like(qr#<a href="/home/kimoto/labo/gitweblite_devrep.git/tree/master">\s*tree\s*</a>#)
  ;
}