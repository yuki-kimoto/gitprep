package Gitprep::Git;
use Mojo::Base -base;

use Carp 'croak';
use Encode qw/encode decode/;
use Encode::Guess;
use Fcntl ':mode';
use File::Basename qw/basename dirname/;
use File::Copy 'move';
use File::Find 'find';
use File::Path qw/mkpath rmtree/;
use POSIX 'floor';
use Gitprep::Util;

# Attributes
has 'bin';
has default_encoding => 'UTF-8';
has 'rep_home';
has text_exts => sub { ['txt'] };
has 'time_zone_second';
has 'app';

sub branch {
  my ($self, $user, $project, $branch_name) = @_;
  
  # Branch
  $branch_name =~ s/^\*//;
  $branch_name =~ s/^\s*//;
  $branch_name =~ s/\s*$//;
  my $branch = {};
  $branch->{name} = $branch_name;
  my $commit = $self->get_commit($user, $project, $branch_name);
  $branch->{commit} = $commit;

  return $branch;
}

sub branch_status {
  my ($self, $user, $project, $branch1, $branch2) = @_;
  
  # Branch status
  my $status = {ahead => 0, behind => 0};
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'rev-list',
    '--left-right',
    "$branch1...$branch2"
  );
  open my $fh, '-|', @cmd
    or croak "Can't get branch status: @cmd";
  while (my $line = <$fh>) {
    if ($line =~ /^</) { $status->{behind}++ }
    elsif ($line =~ /^>/) { $status->{ahead}++ }
  }
  
  return $status;
}

sub no_merged_branch_h {
  my ($self, $user, $project) = @_;
  
  # No merged branches
  my $no_merged_branches_h = {};
  {
    my $rep = $self->rep($user, $project);
    
    my @cmd = $self->cmd_remote($user, $project, 'branch', '--no-merged');
    open my $fh, '-|', @cmd or return;
    my @lines = <$fh>;
    for my $branch_name (@lines) {
      $branch_name = $self->_dec($branch_name);
      $branch_name =~ s/^\*//;
      $branch_name =~ s/^\s*//;
      $branch_name =~ s/\s*$//;
      $no_merged_branches_h->{$branch_name} = 1;
    }
  }
  
  return $no_merged_branches_h;
}

sub branches {
  my ($self, $user, $project) = @_;
  
  # Branches
  my @cmd = $self->cmd_remote($user, $project, 'branch');
  open my $fh, '-|', @cmd or return;
  my $branches = [];
  my $start;
  my $no_merged_branches_h;
  my @lines = <$fh>;
  for my $branch_name (@lines) {
    $branch_name = $self->_dec($branch_name);
    $branch_name =~ s/^\*//;
    $branch_name =~ s/^\s*//;
    $branch_name =~ s/\s*$//;
    
    # No merged branch
    $no_merged_branches_h = $self->no_merged_branch_h($user, $project)
      unless $start++;
    
    # Branch
    my $branch = $self->branch($user, $project, $branch_name);
    $branch->{no_merged} = 1 if $no_merged_branches_h->{$branch_name};
    push @$branches, $branch;
  }
  @$branches = sort { $a->{commit}{age} <=> $b->{commit}{age} } @$branches;
  
  return $branches;
}

sub branches_count {
  my ($self, $user, $project) = @_;
  
  # Branches count
  my @cmd = $self->cmd_remote($user, $project, 'branch');
  open my $fh, '-|', @cmd or return;
  my @branches = <$fh>;
  my $branches_count = @branches;
  
  return $branches_count;
}

sub cmd_remote {
  my ($self, $user, $project, @cmd) = @_;
  
  # Git command
  my $home = $self->rep_home;
  my $rep = "$home/$user/$project.git";
  
  return $self->cmd_remote_dir($rep, @cmd);
}

sub cmd_remote_dir {
  my ($self, $rep, @cmd) = @_;
  
  return ($self->bin, "--git-dir=$rep", @cmd);
}

sub authors {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Authors
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'log',
    '--format=%an',
    $rev,
    '--',
    $file
  );
  open my $fh, "-|", @cmd
    or croak 500, "Open git-cat-file failed";
  my $authors = {};
  my @lines = <$fh>;
  for my $line (@lines) {
    $line = $self->_dec($line);
    $line =~ s/[\r\n]//g;
    $authors->{$line} = 1;
  }
  
  return [sort keys %$authors];
}

sub blame {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Blob
  my $hash = $self->path_to_hash($user, $project, $rev, $file, 'blob')
    or croak 'Cannot find file';
  
  # Git blame
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'blame',
    '--line-porcelain',
    $rev,
    '--',
    $file
  );
  open my $fh, '-|', @cmd
    or croak "Can't git blame --line-porcelain";
  
  # Format lines
  my $blame_lines = [];
  my $blame_line;
  my $max_author_time;
  my $min_author_time;
  my @lines = <$fh>;
  
  my $enc = $self->decide_encoding($user, $project, \@lines);
  for my $line (@lines) {
    $line = decode($enc, $line);
    chomp $line;
    
    if ($blame_line) {
      if ($line =~ /^author +(.+)/) {
        $blame_line->{author} = $1;
      }
      elsif ($line =~ /^author-mail +(.+)/) {
        $blame_line->{author_mail} = $1;
      }
      elsif ($line =~ /^author-time +(.+)/) {
        my $author_time = $1;
        $blame_line->{author_time} = $author_time;
        $max_author_time = $author_time if !$max_author_time || $author_time > $max_author_time;
        $min_author_time = $author_time if !$min_author_time || $author_time < $min_author_time;
        my $author_age_string_date = $self->_age_string_date($author_time);
        $blame_line->{author_age_string_date} = $author_age_string_date;
        my $author_age_string_date_local = $self->_age_string_date_local($author_time);
        $blame_line->{author_age_string_date_local} = $author_age_string_date_local;
      }
      elsif ($line =~ /^summary +(.+)/) {
        $blame_line->{summary} = $1;
      }
      elsif ($line =~ /^\t(.+)?/) {
        my $content = $1;
        $content = '' unless defined $content;
        $blame_line->{content} = $content;
        push @$blame_lines, $blame_line;
        $blame_line = undef;
      }
    }
    elsif ($line =~ /^([a-fA-F0-9]{40}) +\d+ +(\d+)/) {
      $blame_line = {};
      $blame_line->{commit} = $1;
      $blame_line->{number} = $2;
      if ($blame_lines->[-1]
        && $blame_lines->[-1]{commit} eq $blame_line->{commit})
      {
        $blame_line->{before_same_commit} = 1;
      }
    }
  }
  
  my $blame = {
    lines => $blame_lines,
    max_author_time => $max_author_time,
    min_author_time => $min_author_time
  };
  
  return $blame;
}

sub _age_string_date {
  my ($self, $age) = @_;

  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($age);
  my $age_string_date = sprintf '%4d-%02d-%02d', 1900 + $year, $mon + 1, $mday;
  
  return $age_string_date;
}

sub _age_string_date_local {
  my ($self, $age) = @_;
  
  my $time_zone_second = $self->time_zone_second || 0;
  
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($age + $time_zone_second);
  my $age_string_date_local = sprintf '%4d-%02d-%02d', 1900 + $year, $mon + 1, $mday;
  
  return $age_string_date_local;
}

sub blob {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Blob
  my $hash = $self->path_to_hash($user, $project, $rev, $file, 'blob')
    or croak 'Cannot find file';
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'cat-file',
    'blob',
    $hash
  );
  open my $fh, '-|', @cmd
    or croak "Can't cat $file, $hash";
  
  # Format lines
  my @lines = <$fh>;
  my @new_lines;
  my $enc = $self->decide_encoding($user, $project, \@lines);
  for my $line (@lines) {
    $line = decode($enc, $line);
    chomp $line;
    push @new_lines, $line;
  }
  
  return \@new_lines;
}

sub blob_diffs {
  my ($self, $user, $project, $rev1, $rev2, $diff_trees, $opt) = @_;

  $opt ||= {};
  my $ignore_space_change = $opt->{ignore_space_change};
  
  return unless defined $rev1 && defined $rev2;
  
  # Diff tree
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'diff-tree',
    '-r',
    '-M',
    '--no-commit-id',
    '--patch-with-raw',
    ($ignore_space_change ? '--ignore-space-change' : ()),
    $rev1,
    $rev2,
    '--'
  );
  
  open my $fh, '-|', @cmd
    or croak('Open self-diff-tree failed');
  my @diff_tree;
  my @diff_tree_lines = <$fh>;
  my $diff_tree_enc = $self->decide_encoding($user, $project, \@diff_tree_lines);
  for my $line (@diff_tree_lines) {
    $line = decode($diff_tree_enc, $line);
    chomp $line;
    push @diff_tree, $line if $line =~ /^:/;
    last if $line =~ /^\n/;
  }
  close $fh;
  
  # Blob diffs
  my $blob_diffs = [];
  for my $line (@diff_tree) {
  
    # File information
    chomp $line;
    my $diffinfo = $self->parse_diff_tree_line($line);
    my $from_file = $diffinfo->{from_file};
    my $file = $diffinfo->{to_file};
    
    # Blob diff
    my @cmd = $self->cmd_remote(
      $user,
      $project,
      'diff-tree',
      '-r',
      '-M',
      '-p',
      ($ignore_space_change ? '--ignore-space-change' : ()),
      $rev1,
      $rev2,
      '--',
      (defined $from_file ? $from_file : ()),
      $file
    );
    open my $fh, '-|', @cmd
      or croak('Open self-diff-tree failed');
    my @lines = <$fh>;
    my $enc = $self->decide_encoding($user, $project, \@lines);
    @lines = map { decode($enc, $_) } @lines;
    close $fh;
    my ($lines, $diff_info) = $self->parse_blob_diff_lines(\@lines);
    my $blob_diff = {
      file => $file,
      from_file => $from_file,
      lines => $lines,
      add_line_count => $diff_info->{add_line_count},
      delete_line_count => $diff_info->{delete_line_count},
      binary => $diff_info->{binary}
    };
    
    # Diff tree info
    for my $diff_tree (@$diff_trees) {
      if ($diff_tree->{to_file} eq $file) {
        $blob_diff->{status} = $diff_tree->{status};
        $diff_tree->{add_line_count} = $diff_info->{add_line_count};
        $diff_tree->{delete_line_count} = $diff_info->{delete_line_count};
        $diff_tree->{add_block_count} = $diff_info->{add_block_count};
        $diff_tree->{delete_block_count} = $diff_info->{delete_block_count};
        $diff_tree->{binary} = $diff_info->{binary};
        last;
      }
    }
    
    push @$blob_diffs, $blob_diff;
  }
  
  return $blob_diffs;
}

sub blob_is_image {
  my ($self, $user, $project, $rev, $file) = @_;
  
  my $mime_type = $self->blob_mime_type($user, $project, $rev, $file);
  
  return ($mime_type || '') =~ m#^image/#;
}

sub blob_mime_type {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Blob
  my $hash = $self->path_to_hash($user, $project, $rev, $file, 'blob')
    or croak 'Cannot find file';
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'cat-file',
    'blob',
    $hash
  );
  open my $fh, '-|', @cmd
    or croak "Can't cat $file, $hash";

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

sub blob_content_type {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Content type
  my $type = $self->blob_mime_type($user, $project, $rev, $file);
  if ($type eq 'text/plain') {
    $type .= "; charset=" . $self->default_encoding;
  }

  return $type;
}

sub blob_mode {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Blob mode
  $file =~ s#/+$##;
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'ls-tree',
    $rev,
    '--',
    $file
  );
  open my $fh, '-|', @cmd
    or croak 'Open git-ls-tree failed';
  my $line = <$fh>;
  $line = $self->_dec($line);
  close $fh or return;
  my ($mode) = ($line || '') =~ m/^([0-9]+) /;
  
  return $mode;
}

sub blob_raw {
  my ($self, $user, $project, $rev, $path) = @_;
  
  # Blob raw
  my @cmd = $self->cmd_remote($user, $project, 'cat-file', 'blob', "$rev:$path");
  open my $fh, "-|", @cmd
    or croak 500, "Open git-cat-file failed";
  local $/;
  my $blob_raw = scalar <$fh>;

  close $fh or croak 'Reading git-shortlog failed';
  
  return $blob_raw;
}

sub blob_size {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Blob size(KB)
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'cat-file',
    '-s',
    "$rev:$file"
  );
  open my $fh, "-|", @cmd
    or croak 500, "Open cat-file failed";
  my $size = <$fh>;
  $size = $self->_dec($size);
  chomp $size;
  close $fh or croak 'Reading cat-file failed';
  
  # Format
  my $size_f = sprintf('%.3f', $size / 1000);
  $size_f =~ s/0+$//;
  
  return $size_f;
}

sub check_head_link {
  my ($self, $dir) = @_;
  
  # Chack head
  my $head_file = "$dir/HEAD";
  return ((-e $head_file) ||
    (-l $head_file && readlink($head_file) =~ /^refs\/heads\//));
}

sub commits_number {
  my ($self, $user, $project, $ref) = @_;
  
  # Command "git diff-tree"
  my @cmd = $self->cmd_remote($user, $project, 'shortlog', '-s', $ref);
  open my $fh, "-|", @cmd
    or croak 500, "Open git-shortlog failed";
  my @commits_infos = <$fh>;
  @commits_infos = map { chomp; $self->_dec($_) } @commits_infos;
  close $fh or croak 'Reading git-shortlog failed';
  
  my $commits_num = 0;
  for my $commits_info (@commits_infos) {
    if ($commits_info =~ /^ *([0-9]+)/) {
      $commits_num += $1;
    }
  }
  
  return $commits_num;
}

sub exists_branch {
  my ($self, $user, $project) = @_;
  
  # Exists branch
  my $home = $self->rep_home;
  my @cmd = $self->cmd_remote($user, $project, 'branch');
  open my $fh, "-|", @cmd
    or croak 'git branch failed';
  local $/;
  my $branches = <$fh>;
  
  return $branches ne '' ? 1 : 0;
}

sub delete_branch {
  my ($self, $user, $project, $branch) = @_;
  
  my $branches = $self->branches($user, $project);
  my $exists;
  for my $b (@$branches) {
    if ($branch eq $b->{name}) {
      $exists = 1;
      next;
    }
  }
  
  if ($exists) {
    my @cmd = $self->cmd_remote($user, $project, 'branch', '-D', $branch);
    Gitprep::Util::run_command(@cmd)
      or croak "Branch deleting failed. Can't delete branch $branch";
  }
  else {
    croak "Branch deleteting failed.. branchg $branch is not exists";
  }
}

sub description {
  my ($self, $user, $project, $description) = @_;
  
  my $rep = $self->rep($user, $project);
  my $file = "$rep/description";
  
  if (defined $description) {
    # Write description
    open my $fh, '>',$file
      or croak "Can't open file $rep: $!";
    print $fh encode('UTF-8', $description)
      or croak "Can't write description: $!";
    close $fh;
  }
  else {
    # Read description
    return unless -f $file;
    my $description = $self->_slurp($file) || '';
    $description = $self->_dec($description);
    return $description;
  }
}

sub diff_tree {
  my ($self, $user, $project, $rev, $parent, $opt) = @_;
  
  $opt ||= {};
  my $ignore_space_change = $opt->{ignore_space_change};
  
  # Root
  $parent = '--root' unless defined $parent;

  # Get diff tree
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    "diff-tree",
    '-r',
    '--no-commit-id',
    '-M',
    ($ignore_space_change ? '--ignore-space-change' : ()),
    $parent,
    $rev,
    '--'
  );
  
  open my $fh, "-|", @cmd
    or croak 500, "Open git-diff-tree failed";
  my @diff_tree = <$fh>;
  @diff_tree = map { chomp; $self->_dec($_) } @diff_tree;
  close $fh or croak 'Reading git-diff-tree failed';
  
  # Parse "git diff-tree" output
  my $diffs = [];
  for my $line (@diff_tree) {
    my $diff = $self->parsed_diff_tree_line($line);
    
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
  
  return $diffs;
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
  
  # File type long
  if ($mode !~ m/^[0-7]+$/) { return $mode }
  else { $mode = oct $mode }
  if ($self->_s_isgitlink($mode)) { return 'submodule' }
  elsif (S_ISDIR($mode & S_IFMT)) { return 'directory' }
  elsif (S_ISLNK($mode)) { return 'symlink' }
  elsif (S_ISREG($mode)) {
    if ($mode & S_IXUSR) { return 'executable file' }
    else { return 'file' }
  }
  else { return 'unknown' }
  
  return;
}

sub forward_commits {
  my ($self, $user, $project, $rev1, $rev2) = @_;
  
  # Forwarding commits
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'rev-list',
    '--left-right',
    "$rev1...$rev2"
  );
  open my $fh, '-|', @cmd
    or croak "Can't get info: @cmd";
  my $commits = [];
  while (my $line = <$fh>) {
    if ($line =~ /^>(.+)\s/) {
      my $rev = $1;
      my $commit = $self->get_commit($user, $project, $rev);
      push @$commits, $commit;
    }
  }
  
  return $commits;
}

sub path_to_hash {
  my ($self, $user, $project, $rev, $path, $type) = @_;
  
  # Get blob id or tree id (command "git ls-tree")
  $path =~ s#/+$##;
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'ls-tree',
    $rev,
    '--',
    $path
  );
  open my $fh, '-|', @cmd
    or croak 'Open git-ls-tree failed';
  my $line = <$fh>;
  $line = $self->_dec($line);
  close $fh or return;
  my ($t, $id) = ($line || '') =~ m/^[0-9]+ (.+) ([0-9a-fA-F]{40})\t/;
  $t ||= '';
  return if defined $type && $type ne $t;

  return $id;
}


sub last_activity {
  my ($self, $user, $project) = @_;
  
  # Command "git for-each-ref"
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'for-each-ref',
    '--format=%(committer)',
    '--sort=-committerdate',
    '--count=1', 'refs/heads'
  );
  open my $fh, '-|', @cmd or return;
  my $most_recent = <$fh>;
  $most_recent = $self->_dec($most_recent);
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

sub no_merged_branches_count {
  my ($self, $user, $project) = @_;
  
  my @cmd = $self->cmd_remote($user, $project, 'branch', '--no-merged');
  open my $fh, '-|', @cmd or return;
  my @branches = <$fh>;
  my $branches_count = @branches;
  
  return $branches_count;
}

sub path_by_id {
  my ($self, $user, $project, $base, $hash) = @_;
  
  return unless $base;
  return unless $hash;
  
  # Command "git ls-tree"
  my @cmd = $self->cmd_remote($user, $project, 'ls-tree', '-r', '-t', '-z', $base);
  open my $fh, '-|', @cmd or return;

  # Get path
  local $/ = "\0";
  my @lines = <$fh>;
  for my $line (@lines) {
    $line = $self->_dec($line);
    chomp $line;

    if ($line =~ m/(?:[0-9]+) (?:.+) $hash\t(.+)$/) {
      close $fh;
      return $1;
    }
  }
  close $fh;
  
  return;
}

sub parse_rev_path {
  my ($self, $user, $project, $rev_path) = @_;
  
  # References
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'show-ref',
    '--dereference'
  );
  open my $fh, '-|', @cmd
    or return;
  my $refs = [];
  my @lines = <$fh>;
  for my $line (@lines) {
    $line = $self->_dec($line);
    chomp $line;
    if ($line =~ m!^[0-9a-fA-F]{40}\s(refs/((?:heads|tags)/(.*)))$!) {
      push @$refs, $1, $2, $3;
    }
  }
  close $fh or return;
  
  @$refs = sort {
    my @a_match = $a =~ /(\/)/g;
    my @b_match = $b =~ /(\/)/g;
    scalar @b_match <=> scalar @a_match;
  } @$refs;
  
  for my $ref (@$refs) {
    $rev_path =~ m#/$#;
    if ($rev_path =~ m#^(\Q$ref\E)/(.+)#) {
      my $rev = $1;
      my $path = $2;
      return ($rev, $path);
    }
    elsif ($rev_path eq $ref) {
      return ($rev_path, '');
    }
  }
  
  if ($rev_path) {
    my ($rev, $path) = split /\//, $rev_path, 2;
    $path = '' unless defined $path;
    return ($rev, $path);
  }

  return;
}

sub object_type {
  my ($self, $user, $project, $rev) = @_;
  
  # Get object type
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'cat-file',
    '-t',
    $rev
  );
  open my $fh, '-|', @cmd  or return;
  my $type = <$fh>;
  $type = $self->_dec($type);
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
  my @urls = <$fh>;
  @urls = map { chomp; $self->_dec($_) } @urls;
  close $fh;

  return \@urls;
}

sub repository {
  my ($self, $user, $project) = @_;

  return unless -d $self->rep($user, $project);
  

  my $rep = {};
  my @activity = $self->last_activity($user, $project);
  if (@activity) {
    $rep->{age} = $activity[0];
    $rep->{age_string} = $activity[1];
  }
  else { $rep->{age} = 0 }
  
  my $description = $self->description($user, $project) || '';
  $rep->{description} = $self->_chop_str($description, 25, 5);
  
  return $rep;
}

sub references {
  my ($self, $user, $project, $type) = @_;
  
  $type ||= '';
  
  # Branches or tags
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'show-ref',
    '--dereference',
    (
      $type eq 'heads' ? ('--heads') :
      $type eq 'tags' ? ('--tags') :
      ()
    )
  );
  
  open my $fh, '-|', @cmd
    or return;
  
  # Parse references
  my %refs;
  my $type_re = $type ? $type : '(?:heads|tags)';
  my @lines = <$fh>;
  for my $line (@lines) {
    $line = $self->_dec($line);
    chomp $line;
    if ($line =~ m!^([0-9a-fA-F]{40})\srefs/$type_re/(.*)$!) {
      my $rev = $1;
      my $ref = $2;
      $ref =~ s/\^\{\}//;
      if (defined $refs{$rev}) { push @{$refs{$rev}}, $ref }
      else { $refs{$rev} = [$ref] }
    }
  }
  close $fh or return;
  
  return \%refs;
}

sub rep {
  my ($self, $user, $project) = @_;
  
  my $home = $self->rep_home;
  
  return "$home/$user/$project.git";
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

sub tags_count {
  my ($self, $user, $project) = @_;
  
  my $limit = 1000;
  
  # Get tags
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'for-each-ref',
    ($limit ? '--count='.($limit+1) : ()),
    'refs/tags'
  );
  open my $fh, '-|', @cmd or return;
  
  # Tags count
  my @lines = <$fh>;
  
  return scalar @lines;
}

sub tags {
  my ($self, $user, $project, $limit, $count, $offset) = @_;
  
  $limit ||= 1000;
  $count ||= 50;
  $offset ||= 0;
  
  # Get tags
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'for-each-ref',
    ($limit ? '--count='.($limit+1) : ()),
    '--sort=-creatordate',
    '--format=%(objectname) %(objecttype) %(refname) '
      . '%(*objectname) %(*objecttype) %(subject)%00%(creator)',
    'refs/tags'
  );
  open my $fh, '-|', @cmd or return;
  
  
  # Parse Tags
  my @tags;
  my $line_num = 1;
  my @lines = <$fh>;
  for my $line (@lines) {
    $line = $self->_dec($line);
    
    if ($line_num > $offset && $line_num < $offset + $count + 1) {
    
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

      $tag{commit} = $self->get_commit($user, $project, $name);

      push @tags, \%tag;
    }
    $line_num++;
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
  my ($self, $rev, $key, $value) = @_;

  if (!exists $rev->{$key}) { $rev->{$key} = $value }
  elsif (!ref $rev->{$key}) { $rev->{$key} = [ $rev->{$key}, $value ] }
  else { push @{$rev->{$key}}, $value }
}

sub last_change_commit {
  my ($self, $user, $project, $rev, $file) = @_;
  
  my $commit_log = {};
  $file = '' unless defined $file;
  
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    '--no-pager',
    'log',
    '-n',
    '1',
    '--pretty=format:%H', 
    $rev,
    '--',
    $file
  );
  open my $fh, '-|', @cmd
    or croak 'Open git-log failed';
  
  local $/;
  my $commit_log_text = <$fh>;
  $commit_log_text = $self->_dec($commit_log_text);
  
  my $commit;
  if ($commit_log_text =~ /^([0-9a-zA-Z]+)/) {
    my $rev = $1;
    $commit = $self->get_commit($user, $project, $rev);
  }
  
  return $commit;
}

sub parse_blob_diff_lines {
  my ($self, $lines) = @_;

  my $diff_info = {};

  # Parse
  my @lines;
  my $next_before_line_num;
  my $next_after_line_num;
  my $add_line_count = 0;
  my $delete_line_count = 0;
  for my $line (@$lines) {
    
    chomp $line;
    
    my $class;
    my $before_line_num;
    my $after_line_num;
    
    if ($line =~ /^@@\s-(\d+)(?:,\d+)?\s\+(\d+)/) {
      $next_before_line_num = $1;
      $next_after_line_num = $2;
      
      $before_line_num = '...';
      $after_line_num = '...';
      
      $class = 'chunk_header';
    }
    elsif ($line =~ /^\+\+\+/ || $line =~ /^---/) { next }
    elsif ($line =~ /^\-/) {
      $class = 'from_file';
      $before_line_num = $next_before_line_num++;
      $after_line_num = '';
      $delete_line_count++;
    }
    elsif ($line =~ /^\+/) {
      $class = 'to_file';
      $before_line_num = '';
      $after_line_num = $next_after_line_num++;
      $add_line_count++;
    }
    elsif ($line =~ /^Binary files/) {
      $class = 'binary_file';
      $diff_info->{binary} = 1;
    }
    elsif ($line =~ /^ /) {
      $class = 'diff';
      $before_line_num = $next_before_line_num++;
      $after_line_num = $next_after_line_num++;
    }
    else { next }
    
    my $line_data = {
      value => $line,
      class => $class,
      before_line_num => $before_line_num,
      after_line_num => $after_line_num
    };
    push @lines, $line_data;
  }
  
  # Diff info
  my $diff_line_count = $add_line_count + $delete_line_count;
  my $add_block_count
    = $diff_line_count == 0
    ? 0
    : floor(($add_line_count * 5) / $diff_line_count);
  my $delete_block_count
    = $diff_line_count == 0
    ? 0
    : floor(($delete_line_count * 5) / $diff_line_count);
  
  $diff_info->{add_line_count} = $add_line_count;
  $diff_info->{delete_line_count} = $delete_line_count;
  $diff_info->{add_block_count} = $add_block_count;
  $diff_info->{delete_block_count} = $delete_block_count;
  
  return (\@lines, $diff_info);
}

sub get_commit {
  my ($self, $user, $project, $id) = @_;
  
  # Git rev-list
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'rev-list',
    '--parents',
    '--header',
    '--max-count=1',
    $id,
    '--'
  );
  open my $fh, '-|', @cmd
    or croak 'Open git-rev-list failed';
  
  # Parse commit
  local $/ = "\0";
  my $content = <$fh>;
  $content = $self->_dec($content);
  return unless defined $content;
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
  
  # GMT
  {
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($commit{committer_epoch});
    $commit{age_string_date} = sprintf '%4d-%02d-%02d', 1900 + $year, $mon + 1, $mday;
    $commit{age_string_datetime} = sprintf '%4d-%02d-%02d %02d:%02d:%02d',
      1900 + $year, $mon + 1, $mday, $hour, $min, $sec;
  }
  
  # Local Time
  {
    my $time_zone_second = $self->time_zone_second || 0;
    
    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($commit{committer_epoch} + $time_zone_second);
    $commit{age_string_date_local}
      = sprintf '%4d-%02d-%02d', 1900 + $year, $mon + 1, $mday;
    $commit{age_string_datetime_local} = sprintf '%4d-%02d-%02d %02d:%02d:%02d',
      1900 + $year, $mon + 1, $mday, $hour, $min, $sec;
  }

  return \%commit;
}

sub get_commits {
  my ($self, $user, $project, $rev, $maxcount, $skip, $file, @args) = @_;

  # Get Commits
  $maxcount ||= 1;
  $skip ||= 0;
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'rev-list',
    '--header',
    @args,
    ('--max-count=' . $maxcount),
    ('--skip=' . $skip),
    $rev,
    '--',
    (defined $file && length $file ? ($file) : ())
  );
  open my $fh, '-|', @cmd
    or croak 'Open git-rev-list failed';
  
  # Prase Commits text
  local $/ = "\0";
  my @commits;
  my @lines = <$fh>;
  for my $line (@lines) {
    $line = $self->_dec($line);
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

sub parsed_diff_tree_line {
  my ($self, $line) = @_;
  
  return $line if ref $line eq 'HASH';

  return $self->parse_diff_tree_line($line);
}

sub parse_diff_tree_line {
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

sub import_branch {
  my ($self, $user, $project, $branch, $remote_user, $remote_project, $remote_branch, $opt) = @_;
  
  my $force = $opt->{force};
  
  # Git pull
  my $remote_rep = $self->rep($remote_user, $remote_project);
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'fetch',
    $remote_rep,
    ($force ? '+' : '') . "refs/heads/$remote_branch:refs/heads/$branch"
  );
  
  Gitprep::Util::run_command(@cmd)
    or croak 'Open git fetch for import_branch failed';
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

sub separated_commit {
  my ($self, $user, $project, $rev1, $rev2) = @_;
  
  # Command "git diff-tree"
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'show-branch',
    $rev1,
    $rev2
  );
  open my $fh, "-|", @cmd
    or croak 500, "Open git-show-branch failed";

  my $commits = [];
  my $start;
  my @lines = <$fh>;
  my $last_line = pop @lines;
  my $commit;
  if (defined $last_line) {
      my ($id) = $last_line =~ /^.*?\[(.+)?\]/;
      $commit = $self->get_commit($user, $project, $id);
  }

  return $commit;
}

sub snapshot_name {
  my ($self, $project, $rev) = @_;

  my $name = $project;
  $name =~ s,([^/])/*\.git$,$1,;
  $name = basename($name);
  # sanitize name
  $name =~ s/[[:cntrl:]]/?/g;

  my $ver = $rev;
  if ($rev =~ /^[0-9a-fA-F]+$/) {
    my $full_hash = $self->id($project, $rev);
    if ($full_hash =~ /^$rev/ && length($rev) > 7) {
      $ver = $self->short_id($project, $rev);
    }
  } elsif ($rev =~ m!^refs/tags/(.*)$!) {
    $ver = $1;
  } else {
    if ($rev =~ m!^refs/(?:heads|remotes)/(.*)$!) {
      $ver = $1;
    }
    $ver .= '-' . $self->short_id($project, $rev);
  }
  $ver =~ s!/!.!g;

  $name = "$name-$ver";

  return wantarray ? ($name, $name) : $name;
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
  my ($self, $user, $project, $rev, $dir) = @_;
  $dir = '' unless defined $dir;
  
  # Get tree
  my $tid;
  if (defined $dir && $dir ne '') {
    $tid = $self->path_to_hash($user, $project, $rev, $dir, 'tree');
  }
  else {
    my $commit = $self->get_commit($user, $project, $rev);
    $tid = $commit->{tree};
  }
  my @entries = ();
  my $show_sizes = 0;
  my @cmd = $self->cmd_remote(
    $user,
    $project,
    'ls-tree',
    '-z',
    ($show_sizes ? '-l' : ()),
    $tid
  );
  open my $fh, '-|', @cmd
    or $self->croak('Open git-ls-tree failed');
  {
    local $/ = "\0";
    @entries = <$fh>;
    @entries = map { chomp; $self->_dec($_) } @entries;
  }
  close $fh
    or $self->croak(404, "Reading tree failed");

  # Parse tree
  my $trees;
  for my $line (@entries) {
    my $tree = $self->parse_ls_tree_line($line, -z => 1, -l => $show_sizes);
    $tree->{mode_str} = $self->_mode_str($tree->{mode});
    
    # Commit log
    my $path = defined $dir && $dir ne '' ? "$dir/$tree->{name}" : $tree->{name};
    my $commit = $self->last_change_commit($user, $project, $rev, $path);
    $tree->{commit} = $commit;
    
    push @$trees, $tree;
  }
  $trees = [sort {$b->{type} cmp $a->{type} || $a->{name} cmp $b->{name}} @$trees];
  
  return $trees;
}

sub _age_ago {
  my($self,$unit,$age) = @_;

  return $age . " $unit" . ( $unit =~ /^(sec|min)$/ ? "" : ( $age > 1 ? "s" : "" ) ) . " ago";
}

sub _age_string {
  my ($self, $age) = @_;
  my $age_str;

  if ($age >= 60 * 60 * 24 * 365) {
    $age_str = $self->_age_ago(year => (int $age/60/60/24/365));
  } elsif ($age >= 60 * 60 * 24 * (365/12)) {
    $age_str = $self->_age_ago(month => int $age/60/60/24/(365/12));
  } elsif ($age >= 60 * 60 * 24 * 7) {
    $age_str = $self->_age_ago(week => int $age/60/60/24/7);
  } elsif ($age >= 60 * 60 * 24) {
    $age_str = $self->_age_ago(day => int $age/60/60/24);
  } elsif ($age >= 60 * 60) {
    $age_str = $self->_age_ago(hour => int $age/60/60);
  } elsif ($age >= 60) {
    $age_str = $self->_age_ago(min => int $age/60);
  } elsif ($age >= 1) {
    $age_str = $self->_age_ago(sec => int $age);
  } else {
    $age_str .= 'right now';
  }
  
  $age_str =~ s/^1 /a /;
  $age_str =~ s/^a hour/an hour/;
  
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

sub decide_encoding {
  my ($self, $user, $project, $lines) = @_;
  
  my $guess_encoding_str = $self->app->dbi->model('project')->select(
    'guess_encoding',
    where => {user_id => $user, name => $project}
  )->value;
  
  my @guess_encodings;
  if (length $guess_encoding_str) {
    @guess_encodings = split(/\s*,\s*/, $guess_encoding_str);
  }
  
  my $encoding;
  if (@guess_encodings) {
    my @new_lines;
    for (my $i = 0; $i < 100; $i++) {
      last unless defined $lines->[$i];
      push @new_lines, $lines->[$i];
    }
    
    my $str = join('', @new_lines);

    my $ret = Encode::Guess->guess($str, @guess_encodings);
    
    if (ref $ret) {
      $encoding = $ret->name;
    }
    else {
      $encoding = $self->default_encoding
    }
  }
  else {
    $encoding = $self->default_encoding;
  }
  
  return $encoding;
}

sub _dec {
  my ($self, $str) = @_;
  
  my $enc = $self->default_encoding;
  
  $str = decode($enc, $str);
  
  return $str;
}

sub _enc {
  my ($self, $str) = @_;
  
  my $enc = $self->default_encoding;
  
  return encode($enc, $str);
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

sub _slurp {
  my ($self, $file) = @_;
  
  # Slurp
  open my $fh, '<', $file
    or croak qq/Can't open file "$file": $!/;
  my $content = do { local $/; scalar <$fh> };
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

1;
