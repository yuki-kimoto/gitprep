package Gitprep::Git;
use Mojo::Base -base;

use Carp 'croak';
use File::Find 'find';
use File::Basename qw/basename dirname/;
use Fcntl ':mode';

# Encode
use Encode qw/encode decode/;
sub enc {
  my ($self, $str) = @_;
  
  my $enc = $self->encoding;
  
  return encode($enc, $str);
}

sub dec {
  my ($self, $str) = @_;
  
  my $enc = $self->encoding;
  
  my $new_str;
  eval { $new_str = decode($enc, $str) };
  
  return $@ ? $str : $new_str;
}

# Attributes
has 'bin';
has 'search_dirs';
has 'search_max_depth';
has 'encoding';
has 'text_exts';

sub authors {
  my ($self, $rep, $ref, $file) = @_;
  
  # Command "git log FILE"
  my @cmd = ($self->cmd($rep), 'log',  '--format=%an', $ref, '--', $file);
  open my $fh, "-|", @cmd
    or croak 500, "Open git-cat-file failed";
  my $authors = {};
  while (my $line = $self->dec(<$fh>)) {
    $line =~ s/[\r\n]//g;
    $authors->{$line} = 1;
  }
  
  return [sort keys %$authors];
}

sub blob_plain {
  my ($self, $rep, $ref, $path) = @_;
  
  # Command "git diff-tree"
  my @cmd = ($self->cmd($rep), 'cat-file', 'blob', "$ref:$path");
  open my $fh, "-|", @cmd
    or croak 500, "Open git-cat-file failed";
  local $/;
  my $content = $self->dec(scalar <$fh>);
  close $fh or croak 'Reading git-shortlog failed';
  
  return $content;
}

sub blob_mimetype {
  my ($self, $fh, $file) = @_;

  return 'text/plain' unless $fh;
  
  # MIME type
  my $text_exts = $self->text_exts;
  for my $text_ext (@$text_exts) {
    my $ext = quotemeta($text_ext);
    return 'text/plain' if $file =~ /\.$ext$/i;
  }
  if (-T $fh) { return 'text/plain' }
  elsif (! $file) { return 'application/octet-stream' }
  elsif ($file =~ m/\.png$/i) { return 'image/png' }
  elsif ($file =~ m/\.gif$/i) { return 'image/gif' }
  elsif ($file =~ m/\.jpe?g$/i) { return 'image/jpeg'}
  else { return 'application/octet-stream'}
  
  return;
}

sub blob_contenttype {
  my ($self, $fh, $file, $type) = @_;
  
  # Content type
  $type ||= $self->blob_mimetype($fh, $file);
  if ($type eq 'text/plain') {
    $type .= "; charset=" . $self->encoding;
  }

  return $type;
}

sub blob_size_kb {
  my ($self, $rep, $rev, $file) = @_;
  
  # Command "git diff-tree"
  my @cmd = ($self->cmd($rep), 'cat-file', '-s', "$rev:$file");
  open my $fh, "-|", @cmd
    or croak 500, "Open cat-file failed";
  my $size = $self->dec(scalar <$fh>);
  chomp $size;
  close $fh or croak 'Reading cat-file failed';
  
  my $size_kb = sprintf('%.3f', $size / 1024);
  
  return $size_kb;
}

sub check_head_link {
  my ($self, $dir) = @_;
  
  # Chack head
  my $head_file = "$dir/HEAD";
  return ((-e $head_file) ||
    (-l $head_file && readlink($head_file) =~ /^refs\/heads\//));
}

sub cmd {
  my ($self, $project) = @_;
  
  # Execute git command
  return ($self->bin, "--git-dir=$project");
}

sub branch_commits {
  my ($self, $rep, $rev1, $rev2) = @_;
  
  # Command "git diff-tree"
  my @cmd = ($self->cmd($rep), 'show-branch', $rev1, $rev2);
  open my $fh, "-|", @cmd
    or croak 500, "Open git-show-branch failed";

  my $commits = [];
  my $start;
  while (my $line = <$fh>) {
    chomp $line;
    
    if ($start) {
      my ($id) = $line =~ /^.*?\[(.+)?\]/;
      
      next unless $id =~ /^\Q$rev2\E\^?$/ || $id =~ /^\Q$rev2\E^[0-9]+$/;
      
      my $commit = $self->parse_commit($rep, $id);
      
      push @$commits, $commit;
    }
    else {
      if ($line =~ /^-/) {
        $start = 1;
      }
    }
  }
  
  close $fh or croak 'Reading git-show-branch failed';
  
  return $commits;
}

sub separated_commit {
  my ($self, $rep, $rev1, $rev2) = @_;
  
  # Command "git diff-tree"
  my @cmd = ($self->cmd($rep), 'show-branch', $rev1, $rev2);
  open my $fh, "-|", @cmd
    or croak 500, "Open git-show-branch failed";

  my $commits = [];
  my $start;
  my @lines = <$fh>;
  my $last_line = pop @lines;
  my $commit;
  if (defined $last_line) {
      my ($id) = $last_line =~ /^.*?\[(.+)?\]/;
      $commit = $self->parse_commit($rep, $id);
  }

  return $commit;
}

sub commits_number {
  my ($self, $rep, $ref) = @_;
  
  # Command "git diff-tree"
  my @cmd = ($self->cmd($rep), 'shortlog', '-s', $ref);
  open my $fh, "-|", @cmd
    or croak 500, "Open git-shortlog failed";
  my @commits_infos = map { chomp; $self->dec($_) } <$fh>;
  close $fh or croak 'Reading git-shortlog failed';
  
  my $commits_num = 0;
  for my $commits_info (@commits_infos) {
    if ($commits_info =~ /^ *([0-9]+)/) {
      $commits_num += $1;
    }
  }
  
  return $commits_num;
}

sub file_type {
  my ($self, $mode) = @_;
  
  # File type
  if ($mode !~ m/^[0-7]+$/) { return $mode }
  else { $mode = oct $mode }
  if ($self->_s_isgitlink($mode)) { return 'submodule' }
  elsif (S_ISDIR($mode & S_IFMT)) { return 'directory' }
  elsif (S_ISLNK($mode)) { return 'symlink' }
  elsif (S_ISREG($mode)) { return 'file' }
  else { return 'unknown' }
  
  return
}

sub file_type_long {
  my ($self, $mode) = @_;
  
  # File type
  if ($mode !~ m/^[0-7]+$/) { return $mode }
  else { $mode = oct $mode }
  if (S_ISGITLINK($mode)) { return 'submodule' }
  elsif (S_ISDIR($mode & S_IFMT)) { return 'directory' }
  elsif (S_ISLNK($mode)) { return 'symlink' }
  elsif (S_ISREG($mode)) {
    if ($mode & S_IXUSR) { return 'executable' }
    else { return 'file' }
  }
  else { return 'unknown' }
  
  return;
}

sub fill_from_file_info {
  my ($self, $project, $diff, $parents) = @_;
  
  # Fill file info
  $diff->{from_file} = [];
  $diff->{from_file}[$diff->{nparents} - 1] = undef;
  for (my $i = 0; $i < $diff->{nparents}; $i++) {
    if ($diff->{status}[$i] eq 'R' || $diff->{status}[$i] eq 'C') {
      $diff->{from_file}[$i] =
        $self->path_by_id($project, $parents->[$i], $diff->{from_id}[$i]);
    }
  }

  return $diff;
}

sub difftree {
  my ($self, $project, $cid, $parent, $parents) = @_;
  
  # Root
  $parent = '--root' unless defined $parent;

  # Command "git diff-tree"
  my @cmd = ($self->cmd($project), "diff-tree", '-r', '--no-commit-id',
    '-M', (@$parents <= 1 ? $parent : '-c'), $cid, '--');
  open my $fh, "-|", @cmd
    or croak 500, "Open git-diff-tree failed";
  my @difftree = map { chomp; $self->dec($_) } <$fh>;
  close $fh or croak 'Reading git-diff-tree failed';
  
  # Parse "git diff-tree" output
  my $diffs = [];
  my @parents = @$parents;
  for my $line (@difftree) {
    my $diff = $self->parsed_difftree_line($line);
    
    # Parent are more than one
    if (exists $diff->{nparents}) {

      $self->fill_from_file_info($project, $diff, $parents)
        unless exists $diff->{from_file};
      $diff->{is_deleted} = 1 if $self->is_deleted($diff);
      push @$diffs, $diff;
    }
    
    # Parent is single
    else {
      my ($to_mode_oct, $to_mode_str, $to_file_type);
      my ($from_mode_oct, $from_mode_str, $from_file_type);
      if ($diff->{to_mode} ne ('0' x 6)) {
        $to_mode_oct = oct $diff->{to_mode};
        if (S_ISREG($to_mode_oct)) { # only for regular file
          $to_mode_str = sprintf('%04o', $to_mode_oct & 0777); # permission bits
        }
        $to_file_type = $self->file_type($diff->{to_mode});
      }
      if ($diff->{from_mode} ne ('0' x 6)) {
        $from_mode_oct = oct $diff->{from_mode};
        if (S_ISREG($from_mode_oct)) { # only for regular file
          $from_mode_str = sprintf('%04o', $from_mode_oct & 0777); # permission bits
        }
        $from_file_type = $self->file_type($diff->{from_mode});
      }
      
      $diff->{to_mode_str} = $to_mode_str;
      $diff->{to_mode_oct} = $to_mode_oct;
      $diff->{to_file_type} = $to_file_type;
      $diff->{from_mode_str} = $from_mode_str;
      $diff->{from_mode_oct} = $from_mode_oct;
      $diff->{from_file_type} = $from_file_type;

      push @$diffs, $diff;
    }
  }
  
  return $diffs;
}

sub head_id {
  my ($self, $project) = (shift, shift);
  
  # HEAD id
  return $self->id($project, 'HEAD', @_);
};

sub no_merged_branches {
  my ($self, $project) = @_;
  
  # Command "git branch --no-merged"
  my @cmd = ($self->cmd($project), 'branch', '--no-merged');
  open my $fh, '-|', @cmd or return;
  
  my @branch_names = map { s/^\*//; s/^\s*//; s/\s*$//; $self->dec($_) } <$fh>;
  close $fh or croak qq/Can't open "git branch"/;
  
  # Branches
  my $branches = [];
  for my $branch_name (@branch_names) {
    my $branch = {};
    $branch->{name} = $branch_name;
    my $commit = $self->parse_commit($project, $branch_name);
    $branch->{commit} = $commit;
    push @$branches, $branch;
  }
  
  return $branches;
}

sub id {
  my ($self, $project, $ref, @options) = @_;
  
  # Command "git rev-parse" (get commit id)
  my $id;
  my @cmd = ($self->cmd($project), 'rev-parse',
    '--verify', '-q', @options, $ref);
  if (open my $fh, '-|', @cmd) {
    $id = $self->dec(scalar <$fh>);
    chomp $id if defined $id;
    close $fh;
  }
  
  return $id;
}

sub id_by_path {
  my ($self, $project, $commit_id, $path, $type) = @_;
  
  # Get blob id or tree id (command "git ls-tree")
  $path =~ s#/+$##;
  my @cmd = ($self->cmd($project), 'ls-tree', $commit_id, '--', $path);
  open my $fh, '-|', @cmd
    or croak 'Open git-ls-tree failed';
  my $line = $self->dec(scalar <$fh>);
  close $fh or return;
  my ($t, $id) = ($line || '') =~ m/^[0-9]+ (.+) ([0-9a-fA-F]{40})\t/;
  return if defined $type && $type ne $t;

  return $id;
}

sub root_ns {
  my ($self, $root) = @_;

  $root =~ s/^\///;
  
  return $root;
}

sub parse_object {
  my ($self, $project, $id_path) = @_;
  
  # Parse id and path
  my $refs = $self->references($project);
  my $id;
  my $path;
  for my $rs (values %$refs) {
    for my $ref (@$rs) {
      $ref =~ s#^heads/##;
      $ref =~ s#^tags/##;
      if ($id_path =~ s#^\Q$ref(/|$)##) {
        $id = $ref;
        $path = $id_path;
        last;
      }      
    }
  }
  unless (defined $id) {
    if ($id_path =~ s#(^[^/]+)(/|$)##) {
      $id = $1;
      $path = $id_path;
    }
  }
  
  return ($id, $path);
}

sub path_by_id {
  my $self = shift;
  my $project = shift;
  my $base = shift || return;
  my $hash = shift || return;
  
  # Command "git ls-tree"
  my @cmd = ($self->cmd($project), 'ls-tree', '-r', '-t', '-z', $base);
  open my $fh, '-|' or return;

  # Get path
  local $/ = "\0";
  while (my $line = <$fh>) {
    $line = d$line;
    chomp $line;

    if ($line =~ m/(?:[0-9]+) (?:.+) $hash\t(.+)$/) {
      close $fh;
      return $1;
    }
  }
  close $fh;
  
  return;
}

sub project_description {
  my ($self, $project) = @_;
  
  # Description
  my $file = "$project/description";
  my $description = $self->_slurp($file) || '';
  
  return $description;
}

sub last_activity {
  my ($self, $project) = @_;
  
  # Command "git for-each-ref"
  my @cmd = ($self->cmd($project), 'for-each-ref',
    '--format=%(committer)', '--sort=-committerdate',
    '--count=1', 'refs/heads');
  open my $fh, '-|', @cmd or return;
  my $most_recent = $self->dec(scalar <$fh>);
  close $fh or return;
  
  # Parse most recent
  if (defined $most_recent &&
      $most_recent =~ / (\d+) [-+][01]\d\d\d$/) {
    my $timestamp = $1;
    my $age = time - $timestamp;
    return ($age, $self->_age_string($age));
  }
  
  return;
}

sub object_type {
  my ($self, $project, $cid) = @_;
  
  # Get object type (command "git cat-file")
  my @cmd = ($self->cmd($project), 'cat-file', '-t', $cid);
  open my $fh, '-|', @cmd  or return;
  my $type = $self->dec(scalar <$fh>);
  close $fh or return;
  chomp $type;
  
  return $type;
}

sub project_owner {
  my ($self, $project) = @_;
  
  # Project owner
  my $user_id = (stat $project)[4];
  my $user = getpwuid $user_id;
  
  return $user;
}

sub project_urls {
  my ($self, $project) = @_;
  
  # Project URLs
  open my $fh, '<', "$project/cloneurl"
    or return;
  my @urls = map { chomp; $self->dec($_) } <$fh>;
  close $fh;

  return \@urls;
}

sub references {
  my ($self, $project, $type) = @_;
  
  $type ||= '';
  
  # Command "git show-ref" (get references)
  my @cmd = ($self->cmd($project), 'show-ref', '--dereference',
    ($type ? ('--', "refs/$type") : ()));
  open my $fh, '-|', @cmd or return;
  
  # Parse references
  my %refs;
  while (my $line = $self->dec(scalar <$fh>)) {
    chomp $line;
    if ($line =~ m!^([0-9a-fA-F]{40})\srefs/($type.*)$!) {
      if (defined $refs{$1}) { push @{$refs{$1}}, $2 }
      else { $refs{$1} = [$2] }
    }
  }
  close $fh or return;
  
  return \%refs;
}

sub fill_projects {
  my ($self, $home, $ps) = @_;
  
  # Fill rep info
  my @resp;
  for my $rep (@$ps) {
    my (@activity) = $self->last_activity("$home/$rep->{path}");
    next unless @activity;
    ($rep->{age}, $rep->{age_string}) = @activity;
    if (!defined $rep->{descr}) {
      my $descr = $self->project_description("$home/$rep->{path}") || '';
      $rep->{descr_long} = $descr;
      $rep->{descr} = $self->_chop_str($descr, 25, 5);
    }

    push @resp, $rep;
  }

  return \@resp;
}

sub projects {
  my ($self, $dir, %opt) = @_;
  
  my $filter = $opt{filter};
  
  # Repositories
  opendir my $dh, $self->enc($dir)
    or croak qq/Can't open directory $dir: $!/;
  my @reps;
  while (my $rep = readdir $dh) {
    next unless $rep =~ /\.git$/;
    next unless $self->check_head_link("$dir/$rep");
    next if defined $filter && $rep !~ /\Q$filter\E/;
    my $rep_name = $rep;
    $rep_name =~ s/\.git$//;
    push @reps, { name => $rep_name, path => $rep };
  }

  # Fill repositroies information
  for my $rep (@reps) {
    my (@activity) = $self->last_activity("$dir/$rep->{path}");
    next unless @activity;
    ($rep->{age}, $rep->{age_string}) = @activity;
    if (!defined $rep->{descr}) {
      my $descr = $self->project_description("$dir/$rep->{path}") || '';
      $rep->{descr_long} = $descr;
      $rep->{descr} = $self->_chop_str($descr, 25, 5);
    }
  }

  return \@reps;
}

sub short_id {
  my ($self, $project) = (shift, shift);
  
  # Short id
  return $self->id($project, @_, '--short=7');
}

sub tag {
  my ($self, $project, $name) = @_;
  
  # Tag
  my $tags = $self->tags($project);
  for my $tag (@$tags) {
    return $tag if $tag->{name} eq $name;
  }
  
  return;
}

sub tags {
  my ($self, $project, $limit) = @_;
  
  # Get tags (command "git for-each-ref")
  my @cmd = ($self->cmd($project), 'for-each-ref',
    ($limit ? '--count='.($limit+1) : ()), '--sort=-creatordate',
    '--format=%(objectname) %(objecttype) %(refname) '.
    '%(*objectname) %(*objecttype) %(subject)%00%(creator)',
    'refs/tags');
  open my $fh, '-|', @cmd or return;
  
  # Parse Tags
  my @tags;
  while (my $line = $self->dec(scalar <$fh>)) {
    
    my %tag;

    chomp $line;
    my ($refinfo, $creatorinfo) = split(/\0/, $line);
    my ($id, $type, $name, $refid, $reftype, $title) = split(' ', $refinfo, 6);
    my ($creator, $epoch, $tz) =
      ($creatorinfo =~ /^(.*) ([0-9]+) (.*)$/);
    $tag{fullname} = $name;
    $name =~ s!^refs/tags/!!;

    $tag{type} = $type;
    $tag{id} = $id;
    $tag{name} = $name;
    if ($type eq 'tag') {
      $tag{subject} = $title;
      $tag{reftype} = $reftype;
      $tag{refid}   = $refid;
    } else {
      $tag{reftype} = $type;
      $tag{refid}   = $id;
    }

    if ($type eq 'tag' || $type eq 'commit') {
      $tag{epoch} = $epoch;
      if ($epoch) {
        $tag{age} = $self->_age_string(time - $tag{epoch});
      } else {
        $tag{age} = 'unknown';
      }
    }
    
    $tag{comment_short} = $self->_chop_str($tag{subject}, 30, 5)
      if $tag{subject};

    push @tags, \%tag;
  }
  close $fh;

  return \@tags;
}

sub is_deleted {
  my ($self, $diffinfo) = @_;
  
  # Check if deleted
  return $diffinfo->{to_id} eq ('0' x 40);
}

sub id_set_multi {
  my ($self, $cid, $key, $value) = @_;

  if (!exists $cid->{$key}) { $cid->{$key} = $value }
  elsif (!ref $cid->{$key}) { $cid->{$key} = [ $cid->{$key}, $value ] }
  else { push @{$cid->{$key}}, $value }
}

sub latest_commit_log {
  my ($self, $rep, $ref, $file) = @_;
  
  my $commit_log = {};
  $file = '' unless defined $file;
  
  my @cmd = ($self->cmd($rep), '--no-pager', 'log',
    '-n', '1',
    '--pretty=format:%H - %an - %ar : %s', 
    $ref, '--', $file);
  open my $fh, '-|', @cmd
    or croak 'Open git-log failed';
  
  local $/;
  my $commit_log_text = $self->dec(scalar <$fh>);

  if ($commit_log_text =~ /^([0-9a-zA-Z]+) - (.+) - (.+?) : (.+)/) {
    $commit_log->{commit} = $1;
    $commit_log->{author} = $2;
    $commit_log->{author_date} = $3;
    $commit_log->{comment} = substr($4, 0, 60) . '...';
  }
  
  $commit_log->{author_date} =~ s/,.*$//;
  $commit_log->{author_date} =~ s/ +ago.*$//;
  $commit_log->{author_date} .= ' ago';
  
  return $commit_log;
}

sub parse_blobdiff_lines {
  my ($self, $lines_raw) = @_;
  
  # Parse
  my @lines;
  for my $line (@$lines_raw) {
    $line = $self->dec($line);
    chomp $line;
    my $class;
    
    if ($line =~ /^diff \-\-git /) { $class = 'diff header' }
    elsif ($line =~ /^index /) { $class = 'diff extended_header' }
    elsif ($line =~ /^\+/) { $class = 'diff to_file' }
    elsif ($line =~ /^\-/) { $class = 'diff from_file' }
    elsif ($line =~ /^\@\@/) { $class = 'diff chunk_header' }
    elsif ($line =~ /^Binary files/) { $class = 'diff binary_file' }
    else { $class = 'diff' }
    push @lines, {value => $line, class => $class};
  }
  
  return \@lines;
}

sub parse_commit {
  my ($self, $project, $id) = @_;
  
  # Git rev-list
  my @cmd = ($self->cmd($project), 'rev-list', '--parents',
    '--header', '--max-count=1', $id, '--');
  open my $fh, '-|', @cmd
    or croak 'Open git-rev-list failed';
  
  # Parse commit
  local $/ = "\0";
  my $content = $self->dec(scalar <$fh>);
  my $commit = $self->parse_commit_text($content, 1);
  close $fh;

  return $commit;
}

sub parse_commit_text {
  my ($self, $commit_text, $withparents) = @_;
  
  my @commit_lines = split '\n', $commit_text;
  my %commit;

  pop @commit_lines; # Remove '\0'
  return unless @commit_lines;

  my $header = shift @commit_lines;
  return if $header !~ m/^[0-9a-fA-F]{40}/;
  
  ($commit{id}, my @parents) = split ' ', $header;
  while (my $line = shift @commit_lines) {
    last if $line eq "\n";
    if ($line =~ m/^tree ([0-9a-fA-F]{40})$/) {
      $commit{tree} = $1;
    } elsif ((!defined $withparents) && ($line =~ m/^parent ([0-9a-fA-F]{40})$/)) {
      push @parents, $1;
    } elsif ($line =~ m/^author (.*) ([0-9]+) (.*)$/) {
      $commit{author} = $1;
      $commit{author_epoch} = $2;
      $commit{author_tz} = $3;
      if ($commit{author} =~ m/^([^<]+) <([^>]*)>/) {
        $commit{author_name}  = $1;
        $commit{author_email} = $2;
      } else {
        $commit{author_name} = $commit{author};
      }
    } elsif ($line =~ m/^committer (.*) ([0-9]+) (.*)$/) {
      $commit{committer} = $1;
      $commit{committer_epoch} = $2;
      $commit{committer_tz} = $3;
      if ($commit{committer} =~ m/^([^<]+) <([^>]*)>/) {
        $commit{committer_name}  = $1;
        $commit{committer_email} = $2;
      } else {
        $commit{committer_name} = $commit{committer};
      }
    }
  }
  return unless defined $commit{tree};
  $commit{parents} = \@parents;
  $commit{parent} = $parents[0];

  for my $title (@commit_lines) {
    $title =~ s/^    //;
    if ($title ne '') {
      $commit{title} = $self->_chop_str($title, 80, 5);
      # remove leading stuff of merges to make the interesting part visible
      if (length($title) > 50) {
        $title =~ s/^Automatic //;
        $title =~ s/^merge (of|with) /Merge ... /i;
        if (length($title) > 50) {
          $title =~ s/(http|rsync):\/\///;
        }
        if (length($title) > 50) {
          $title =~ s/(master|www|rsync)\.//;
        }
        if (length($title) > 50) {
          $title =~ s/kernel.org:?//;
        }
        if (length($title) > 50) {
          $title =~ s/\/pub\/scm//;
        }
      }
      $commit{title_short} = $self->_chop_str($title, 50, 5);
      last;
    }
  }
  if (! defined $commit{title} || $commit{title} eq '') {
    $commit{title} = $commit{title_short} = '(no commit message)';
  }
  # remove added spaces
  for my $line (@commit_lines) {
    $line =~ s/^    //;
  }
  $commit{comment} = \@commit_lines;

  my $age = time - $commit{committer_epoch};
  $commit{age} = $age;
  $commit{age_string} = $self->_age_string($age);
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($commit{committer_epoch});
  if ($age > 60*60*24*7*2) {
    $commit{age_string_date} = sprintf '%4i-%02u-%02i', 1900 + $year, $mon+1, $mday;
    $commit{age_string_age} = $commit{age_string};
  } else {
    $commit{age_string_date} = $commit{age_string};
    $commit{age_string_age} = sprintf '%4i-%02u-%02i', 1900 + $year, $mon+1, $mday;
  }
  return \%commit;
}

sub parse_commits {
  my ($self, $project, $cid, $maxcount, $skip, $file, @args) = @_;

  # git rev-list
  $maxcount ||= 1;
  $skip ||= 0;
  my @cmd = ($self->cmd($project), 'rev-list', '--header', @args,
    ('--max-count=' . $maxcount), ('--skip=' . $skip), $cid, '--',
    (defined $file ? ($file) : ()));
  open my $fh, '-|', @cmd
    or croak 'Open git-rev-list failed';

  # Parse rev-list results
  local $/ = "\0";
  my @commits;
  while (my $line = $self->dec(scalar <$fh>)) {
    my $commit = $self->parse_commit_text($line);
    push @commits, $commit;
  }
  close $fh;

  return \@commits;
}

sub parse_date {
  my $self = shift;
  my $epoch = shift;
  my $tz = shift || '-0000';
  
  # Parse data
  my %date;
  my @months = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
  my @days = qw/Sun Mon Tue Wed Thu Fri Sat/;
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime $epoch;
  $date{hour} = $hour;
  $date{minute} = $min;
  $date{mday} = $mday;
  $date{day} = $days[$wday];
  $date{month} = $months[$mon];
  $date{rfc2822} = sprintf '%s, %d %s %4d %02d:%02d:%02d +0000',
    $days[$wday], $mday, $months[$mon], 1900 + $year, $hour ,$min, $sec;
  $date{'mday-time'} = sprintf '%d %s %02d:%02d',
    $mday, $months[$mon], $hour ,$min;
  $date{'iso-8601'}  = sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ',
    1900 + $year, 1+$mon, $mday, $hour ,$min, $sec;
  my ($tz_sign, $tz_hour, $tz_min) = ($tz =~ m/^([-+])(\d\d)(\d\d)$/);
  $tz_sign = ($tz_sign eq '-' ? -1 : +1);
  my $local = $epoch + $tz_sign * ((($tz_hour*60) + $tz_min) * 60);
  ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime $local;
  $date{hour_local} = $hour;
  $date{minute_local} = $min;
  $date{tz_local} = $tz;
  $date{'iso-tz'} = sprintf('%04d-%02d-%02d %02d:%02d:%02d %s',
    1900 + $year, $mon+1, $mday, $hour, $min, $sec, $tz);
  
  return \%date;
}

sub parsed_difftree_line {
  my ($self, $line) = @_;
  
  return $line if ref $line eq 'HASH';

  return $self->parse_difftree_raw_line($line);
}

sub parse_difftree_raw_line {
  my ($self, $line) = @_;

  my %res;
  if ($line =~ m/^:([0-7]{6}) ([0-7]{6}) ([0-9a-fA-F]{40}) ([0-9a-fA-F]{40}) (.)([0-9]{0,3})\t(.*)$/) {
    $res{from_mode} = $1;
    $res{to_mode} = $2;
    $res{from_id} = $3;
    $res{to_id} = $4;
    $res{status} = $5;
    $res{similarity} = $6;
    if ($res{status} eq 'R' || $res{status} eq 'C') {
      ($res{from_file}, $res{to_file}) = map { $self->_unquote($_) } split("\t", $7);
    } else {
      $res{from_file} = $res{to_file} = $res{file} = $self->_unquote($7);
    }
  }
  elsif ($line =~ s/^(::+)((?:[0-7]{6} )+)((?:[0-9a-fA-F]{40} )+)([a-zA-Z]+)\t(.*)$//) {
    $res{nparents}  = length($1);
    $res{from_mode} = [ split(' ', $2) ];
    $res{to_mode} = pop @{$res{from_mode}};
    $res{from_id} = [ split(' ', $3) ];
    $res{to_id} = pop @{$res{from_id}};
    $res{status} = [ split('', $4) ];
    $res{to_file} = $self->_unquote($5);
  }
  elsif ($line =~ m/^([0-9a-fA-F]{40})$/) { $res{commit} = $1 }

  return \%res;
}

sub parse_ls_tree_line {
  my ($self, $line) = @_;
  my %opts = @_;
  my %res;

  if ($opts{'-l'}) {
    $line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40}) +(-|[0-9]+)\t(.+)$/s;

    $res{mode} = $1;
    $res{type} = $2;
    $res{hash} = $3;
    $res{size} = $4;
    if ($opts{'-z'}) { $res{name} = $5 }
    else { $res{name} = $self->_unquote($5) }
  }
  else {
    $line =~ m/^([0-9]+) (.+) ([0-9a-fA-F]{40})\t(.+)$/s;

    $res{mode} = $1;
    $res{type} = $2;
    $res{hash} = $3;
    if ($opts{'-z'}) { $res{name} = $4 }
    else { $res{name} = $self->_unquote($4) }
  }

  return \%res;
}

sub parse_tag {
  my ($self, $project, $tag_id) = @_;
  
  # Get tag (command "git cat-file")
  my @cmd = ($self->cmd($project), 'cat-file', 'tag', $tag_id);
  open my $fh, '-|', @cmd or return;
  
  # Parse tag
  my %tag;
  my @comment;
  $tag{id} = $tag_id;
  while (my $line = $self->dec(scalar <$fh>)) {
    chomp $line;
    if ($line =~ m/^object ([0-9a-fA-F]{40})$/) { $tag{object} = $1 }
    elsif ($line =~ m/^type (.+)$/) { $tag{type} = $1 }
    elsif ($line =~ m/^tag (.+)$/) { $tag{name} = $1 }
    elsif ($line =~ m/^tagger (.*) ([0-9]+) (.*)$/) {
      $tag{author} = $1;
      $tag{author_epoch} = $2;
      $tag{author_tz} = $3;
      if ($tag{author} =~ m/^([^<]+) <([^>]*)>/) {
        $tag{author_name}  = $1;
        $tag{author_email} = $2;
      } else { $tag{author_name} = $tag{author} }
    } elsif ($line =~ m/--BEGIN/) { 
      push @comment, $line;
      last;
    } elsif ($line eq '') { last }
  }
  my $comment = $self->dec(scalar <$fh>);
  push @comment, $comment;
  $tag{comment} = \@comment;
  close $fh or return;
  return unless defined $tag{name};
  
  return \%tag;
}

sub search_bin {
  my $self = shift;
  
  # Search git bin
  my $env_path = $ENV{PATH};
  my @paths = split /:/, $env_path;
  for my $path (@paths) {
    $path =~ s#/$##;
    my $bin = "$path/git";
    if (-f $bin) {
      return $bin;
      last;
    }
  }
  
  my $local_bin = '/usr/local/bin/git';
  return $local_bin if -f $local_bin;
  
  my $bin = '/usr/bin/git';
  return $bin if -f $bin;
  
  return;
}

sub search_projects {
  my ($self, %opt) = @_;
  my $dirs = $self->search_dirs;
  my $max_depth = $self->search_max_depth;
  
  # Search
  my @projects;
  for my $dir (@$dirs) {
    next unless -d $dir;
  
    $dir =~ s/\/$//;
    my $prefix_length = length($dir);
    my $prefix_depth = 0;
    for my $c (split //, $dir) {
      $prefix_depth++ if $c eq '/';
    }
    
    no warnings 'File::Find';
    File::Find::find({
      follow_fast => 1,
      follow_skip => 2,
      dangling_symlinks => 0,
      wanted => sub {
        my $path = $File::Find::name;
        my $base_path = $_;
        
        return if (m!^[/.]$!);
        return unless -d $base_path;
        
        if ($base_path eq '.git') {
          $File::Find::prune = 1;
          return;
        };
        
        my $depth = 0;
        for my $c (split //, $dir) {
          $depth++ if $c eq '/';
        }
        
        if ($depth - $prefix_depth > $max_depth) {
          $File::Find::prune = 1;
          return;
        }
        
        if (-d $path) {
          if ($self->check_head_link($path)) {
            my $home = dirname $path;
            my $name = basename $path;
            push @projects, {home => $home, name => $name};
            $File::Find::prune = 1;
          }
        }
      },
    }, $dir);
  }
  
  return \@projects;
}

sub snapshot_name {
  my ($self, $project, $cid) = @_;

  my $name = $project;
  $name =~ s,([^/])/*\.git$,$1,;
  $name = basename($name);
  # sanitize name
  $name =~ s/[[:cntrl:]]/?/g;

  my $ver = $cid;
  if ($cid =~ /^[0-9a-fA-F]+$/) {
    my $full_hash = $self->id($project, $cid);
    if ($full_hash =~ /^$cid/ && length($cid) > 7) {
      $ver = $self->short_id($project, $cid);
    }
  } elsif ($cid =~ m!^refs/tags/(.*)$!) {
    $ver = $1;
  } else {
    if ($cid =~ m!^refs/(?:heads|remotes)/(.*)$!) {
      $ver = $1;
    }
    $ver .= '-' . $self->short_id($project, $cid);
  }
  $ver =~ s!/!.!g;

  $name = "$name-$ver";

  return wantarray ? ($name, $name) : $name;
}

sub _age_string {
  my ($self, $age) = @_;
  my $age_str;

  if ($age > 60*60*24*365*2) {
    $age_str = (int $age/60/60/24/365);
    $age_str .= ' years ago';
  } elsif ($age > 60*60*24*(365/12)*2) {
    $age_str = int $age/60/60/24/(365/12);
    $age_str .= ' months ago';
  } elsif ($age > 60*60*24*7*2) {
    $age_str = int $age/60/60/24/7;
    $age_str .= ' weeks ago';
  } elsif ($age > 60*60*24*2) {
    $age_str = int $age/60/60/24;
    $age_str .= ' days ago';
  } elsif ($age > 60*60*2) {
    $age_str = int $age/60/60;
    $age_str .= ' hours ago';
  } elsif ($age > 60*2) {
    $age_str = int $age/60;
    $age_str .= ' min ago';
  } elsif ($age > 2) {
    $age_str = int $age;
    $age_str .= ' sec ago';
  } else {
    $age_str .= ' right now';
  }
  return $age_str;
}

sub _chop_str {
  my $self = shift;
  my $str = shift;
  my $len = shift;
  my $add_len = shift || 10;
  my $where = shift || 'right';

  if ($where eq 'center') {
    # Filler is length 5
    return $str if ($len + 5 >= length($str));
    $len = int($len/2);
  } else {
    # Filler is length 4
    return $str if ($len + 4 >= length($str)); 
  }

  # Regexps: ending and beginning with word part up to $add_len
  my $endre = qr/.{$len}\w{0,$add_len}/;
  my $begre = qr/\w{0,$add_len}.{$len}/;

  if ($where eq 'left') {
    $str =~ m/^(.*?)($begre)$/;
    my ($lead, $body) = ($1, $2);
    if (length($lead) > 4) {
      $lead = ' ...';
    }
    return "$lead$body";

  } elsif ($where eq 'center') {
    $str =~ m/^($endre)(.*)$/;
    my ($left, $str)  = ($1, $2);
    $str =~ m/^(.*?)($begre)$/;
    my ($mid, $right) = ($1, $2);
    if (length($mid) > 5) {
      $mid = ' ... ';
    }
    return "$left$mid$right";

  } else {
    $str =~ m/^($endre)(.*)$/;
    my $body = $1;
    my $tail = $2;
    if (length($tail) > 4) {
      $tail = '... ';
    }
    return "$body$tail";
  }
}

sub _mode_str {
  my $self = shift;
  my $mode = oct shift;

  # Mode to string
  if ($self->_s_isgitlink($mode)) { return 'm---------' }
  elsif (S_ISDIR($mode & S_IFMT)) { return 'drwxr-xr-x' }
  elsif (S_ISLNK($mode)) { return 'lrwxrwxrwx' }
  elsif (S_ISREG($mode)) {
    if ($mode & S_IXUSR) {
      return '-rwxr-xr-x';
    } else {
      return '-rw-r--r--'
    }
  } else { return '----------' }
  
  return;
}

sub _s_isgitlink {
  my ($self, $mode) = @_;
  
  # Check if git link
  my $s_ifgitlink = 0160000;
  return (($mode & S_IFMT) == $s_ifgitlink)
}

sub timestamp {
  my ($self, $date) = @_;
  
  # Time stamp
  my $strtime = $date->{rfc2822};
  my $localtime_format = '(%02d:%02d %s)';
  if ($date->{hour_local} < 6) { $localtime_format = '(%02d:%02d %s)' }
  $strtime .= ' ' . sprintf(
    $localtime_format,
    $date->{hour_local},
    $date->{minute_local},
    $date->{tz_local}
  );

  return $strtime;
}

sub trees {
  my ($self, $rep, $tid, $ref, $dir) = @_;
  
  # Get tree (command "git ls-tree")
  my @entries = ();
  my $show_sizes = 0;
  open my $fh, '-|', $self->cmd($rep), 'ls-tree', '-z',
      ($show_sizes ? '-l' : ()), $tid
    or $self->croak('Open git-ls-tree failed');
  {
    local $/ = "\0";
    @entries = map { chomp; $self->dec($_) } <$fh>;
  }
  close $fh
    or $self->croak(404, "Reading tree failed");

  # Parse tree
  my $trees;
  for my $line (@entries) {
    my $tree = $self->parse_ls_tree_line($line, -z => 1, -l => $show_sizes);
    $tree->{mode_str} = $self->_mode_str($tree->{mode});
    
    # Commit log
    my $name = defined $dir && $dir ne '' ? "$dir/$tree->{name}" : $tree->{name};
    my $commit_log = $self->latest_commit_log($rep, $ref, $name);
    $tree = {%$tree, %$commit_log};
    
    push @$trees, $tree;
  }
  $trees = [sort {$b->{type} cmp $a->{type} || $a->{name} cmp $b->{name}} @$trees];
  
  return $trees;
}

sub _slurp {
  my ($self, $file) = @_;
  
  # Slurp
  open my $fh, '<', $file
    or croak qq/Can't open file "$file": $!/;
  my $content = do { local $/; $self->dec(scalar <$fh>) };
  close $fh;
  
  return $content;
}

sub _unquote {
  my ($self, $str) = @_;
  
  # Unquote function
  my $unq = sub {
    my $seq = shift;
    my %escapes = (
      t => "\t",
      n => "\n",
      r => "\r",
      f => "\f",
      b => "\b",
      a => "\a",
      e => "\e",
      v => "\013",
    );

    if ($seq =~ m/^[0-7]{1,3}$/) { return chr oct $seq }
    elsif (exists $escapes{$seq}) { return $escapes{$seq} }
    
    return $seq;
  };
  
  # Unquote
  if ($str =~ m/^"(.*)"$/) {
    $str = $1;
    $str =~ s/\\([^0-7]|[0-7]{1,3})/$unq->($1)/eg;
  }
  
  return $str;
}

sub _tab_to_space {
  my ($self, $line) = @_;
  
  # Tab to space
  while ((my $pos = index($line, "\t")) != -1) {
    if (my $count = (2 - ($pos % 2))) {
      my $spaces = ' ' x $count;
      $line =~ s/\t/$spaces/;
    }
  }

  return $line;
}

1;
