package Gitprep::Git;
use Mojo::Base -base;

use Carp 'croak';
use Encode qw/encode decode/;
use Fcntl ':mode';
use File::Basename qw/basename dirname/;
use File::Copy 'move';
use File::Find 'find';
use File::Path qw/mkpath rmtree/;

# Attributes
has 'bin';
has encoding => 'UTF-8';
has 'rep_home';
has text_exts => sub { ['txt'] };

sub cmd {
  my ($self, $user, $project, @cmd) = @_;
  
  # Git command
  my $home = $self->rep_home;
  my $rep = "$home/$user/$project.git";
  
  return $self->cmd_rep($rep, @cmd);
}

sub cmd_rep {
  my ($self, $rep, @cmd) = @_;
  
  return ($self->bin, "--git-dir=$rep", @cmd);
}

sub authors {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Authors
  my @cmd = $self->cmd(
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
  while (my $line = $self->_dec(<$fh>)) {
    $line =~ s/[\r\n]//g;
    $authors->{$line} = 1;
  }
  
  return [sort keys %$authors];
}

sub blob_diffs {
  my ($self, $user, $project, $rev1, $rev2, $diff_trees) = @_;
  
  return unless defined $rev1 && defined $rev2;
  
  # Diff tree
  my @cmd = $self->cmd(
    $user,
    $project,
    'diff-tree',
    '-r',
    '-M',
    '--no-commit-id',
    '--patch-with-raw',
    $rev1,
    $rev2,
    '--'
  );
  open my $fh, '-|', @cmd
    or croak('Open self-diff-tree failed');
  my @diff_tree;
  while (my $line = $self->_dec(scalar <$fh>)) {
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
    my $diffinfo = $self->parse_diff_tree_raw_line($line);
    my $from_file = $diffinfo->{from_file};
    my $file = $diffinfo->{to_file};
    
    # Blob diff
    my @cmd = $self->cmd(
      $user,
      $project,
      'diff-tree',
      '-r',
      '-M',
      '-p',
      $rev1,
      $rev2,
      '--',
      (defined $from_file ? $from_file : ()),
      $file
    );
    open my $fh_blob_diff, '-|', @cmd
      or croak('Open self-diff-tree failed');
    my @lines = map { $self->_dec($_) } <$fh_blob_diff>;
    close $fh_blob_diff;
    my $blob_diff = {
      file => $file,
      from_file => $from_file,
      lines => $self->parse_blob_diff_lines(\@lines)
    };
    
    # Status
    for my $diff_tree (@$diff_trees) {
      if ($diff_tree->{to_file} eq $file) {
        $blob_diff->{status} = $diff_tree->{status};
        last;
      }
    }
    push @$blob_diffs, $blob_diff;
  }
  
  return $blob_diffs;
}

sub blob {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Blob content
  my $bid = $self->id_by_path($user, $project, $rev, $file, 'blob')
    or croak 'Cannot find file';
  my @cmd = $self->cmd(
    $user,
    $project,
    'cat-file',
    'blob',
    $bid
  );
  open my $fh, '-|', @cmd
    or croak "Can't cat $file, $bid";
  
  # Parse lines
  my $lines =[];
  while (my $line = $self->_dec(scalar <$fh>)) {
    chomp $line;
    $line = $self->_tab_to_space($line);
    push @$lines, $line;
  }
  
  return $lines;
}

sub blob_plain {
  my ($self, $user, $project, $rev, $path) = @_;
  
  # Get blob
  my @cmd = $self->cmd($user, $project, 'cat-file', 'blob', "$rev:$path");
  open my $fh, "-|", @cmd
    or croak 500, "Open git-cat-file failed";
  local $/;
  my $content = $self->_dec(scalar <$fh>);
  close $fh or croak 'Reading git-shortlog failed';
  
  return $content;
}

sub blob_mimetype {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Blob content
  my $bid = $self->id_by_path($user, $project, $rev, $file, 'blob')
    or croak 'Cannot find file';
  my @cmd = $self->cmd(
    $user,
    $project,
    'cat-file',
    'blob',
    $bid
  );
  open my $fh, '-|', @cmd
    or croak "Can't cat $file, $bid";

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
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Content type
  my $type = $self->blob_mimetype($user, $project, $rev, $file);
  if ($type eq 'text/plain') {
    $type .= "; charset=" . $self->encoding;
  }

  return $type;
}

sub blob_mode {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Mode
  $file =~ s#/+$##;
  my @cmd = $self->cmd(
    $user,
    $project,
    'ls-tree',
    $rev,
    '--',
    $file
  );
  open my $fh, '-|', @cmd
    or croak 'Open git-ls-tree failed';
  my $line = $self->_dec(scalar <$fh>);
  close $fh or return;
  my ($mode) = ($line || '') =~ m/^([0-9]+) /;
  
  return $mode;
}

sub blob_raw {
  my ($self, $user, $project, $rev, $path) = @_;
  
  # Get blob raw
  my @cmd = $self->cmd($user, $project, 'cat-file', 'blob', "$rev:$path");
  open my $fh, "-|", @cmd
    or croak 500, "Open git-cat-file failed";
  local $/;
  my $blob_raw = scalar <$fh>;

  close $fh or croak 'Reading git-shortlog failed';
  
  return $blob_raw;
}

sub blob_size_kb {
  my ($self, $user, $project, $rev, $file) = @_;
  
  # Command "git diff-tree"
  my @cmd = $self->cmd(
    $user,
    $project,
    'cat-file',
    '-s',
    "$rev:$file"
  );
  open my $fh, "-|", @cmd
    or croak 500, "Open cat-file failed";
  my $size = $self->_dec(scalar <$fh>);
  chomp $size;
  close $fh or croak 'Reading cat-file failed';
  
  my $size_kb = sprintf('%.3f', $size / 1000);
  
  $size_kb =~ s/0+$//;
  
  return $size_kb;
}

sub branch_exists {
  my ($self, $user, $project) = @_;
  
  my $home = $self->rep_home;

  my @cmd = $self->cmd($user, $project, 'branch');
  open my $fh, "-|", @cmd
    or croak 'git branch failed';
  
  local $/;
  my $branches = <$fh>;
  
  return $branches eq '' ? 0 : 1;
}

sub branch_commits {
  my ($self, $user, $project, $rev1, $rev2) = @_;
  
  # Get bramcj commits
  my @cmd = $self->cmd(
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
  while (my $line = <$fh>) {
    chomp $line;
    
    if ($start) {
      my ($id) = $line =~ /^.*?\[(.+)?\]/;
      
      next unless $id =~ /^\Q$rev2\E\^?$/ || $id =~ /^\Q$rev2\E^[0-9]+$/;
      
      my $commit = $self->get_commit($user, $project, $id);
      
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

sub branch_diff {
  my ($self, $user, $project, $branch1, $branch2) = @_;
  
  my @cmd = $self->cmd(
    $user,
    $project,
    'rev-list',
    '--left-right',
    "$branch1...$branch2"
  );
  open my $fh, '-|', @cmd
    or croak "Can't get branch status: @cmd";
  
  my $commits = [];
  while (my $line = <$fh>) {
    if ($line =~ /^>(.+)\s/) {
      my $commit_id = $1;
      my $commit = $self->get_commit($user, $project, $commit_id);
      push @$commits, $commit;
    }
  }
  
  return $commits;
}

sub branch_status {
  my ($self, $user, $project, $branch1, $branch2) = @_;
  
  my $status = {ahead => 0, behind => 0};
  my @cmd = $self->cmd(
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
  my @cmd = $self->cmd($user, $project, 'shortlog', '-s', $ref);
  open my $fh, "-|", @cmd
    or croak 500, "Open git-shortlog failed";
  my @commits_infos = map { chomp; $self->_dec($_) } <$fh>;
  close $fh or croak 'Reading git-shortlog failed';
  
  my $commits_num = 0;
  for my $commits_info (@commits_infos) {
    if ($commits_info =~ /^ *([0-9]+)/) {
      $commits_num += $1;
    }
  }
  
  return $commits_num;
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
    my @cmd = $self->cmd($user, $project, 'branch', '-D', $branch);
    system(@cmd) == 0
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
    my $description = $self->_slurp($file) || '';
    return $description;
  }
}

sub diff_tree {
  my ($self, $user, $project, $cid, $parent, $parents) = @_;
  
  # Root
  $parent = '--root' unless defined $parent;

  # Get diff tree
  my @cmd = $self->cmd(
    $user,
    $project,
    "diff-tree",
    '-r',
    '--no-commit-id',
    '-M',
    (@$parents <= 1 ? $parent : '-c'),
    $cid,
    '--'
  );
  open my $fh, "-|", @cmd
    or croak 500, "Open git-diff-tree failed";
  my @diff_tree = map { chomp; $self->_dec($_) } <$fh>;
  close $fh or croak 'Reading git-diff-tree failed';
  
  # Parse "git diff-tree" output
  my $diffs = [];
  my @parents = @$parents;
  for my $line (@diff_tree) {
    my $diff = $self->parsed_diff_tree_line($line);
    
    # Parent are more than one
    if (exists $diff->{nparents}) {

      $self->fill_from_file_info($user, $project, $diff, $parents)
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

sub fill_from_file_info {
  my ($self, $user, $project, $diff, $parents) = @_;
  
  # Fill file info
  $diff->{from_file} = [];
  $diff->{from_file}[$diff->{nparents} - 1] = undef;
  for (my $i = 0; $i < $diff->{nparents}; $i++) {
    if ($diff->{status}[$i] eq 'R' || $diff->{status}[$i] eq 'C') {
      $diff->{from_file}[$i] =
        $self->path_by_id($user, $project, $parents->[$i], $diff->{from_id}[$i]);
    }
  }

  return $diff;
}

sub branches {
  my ($self, $user, $project, $opts) = @_;
  
  # No merged branches
  my $no_merged_branches_h = {};
  {
    my @cmd = $self->cmd($user, $project, 'branch');
    push @cmd, , '--no-merged';
    open my $fh, '-|', @cmd or return;
    
    while (my $branch_name = $self->_dec(scalar <$fh>)) {
      $branch_name =~ s/^\*//;
      $branch_name =~ s/^\s*//;
      $branch_name =~ s/\s*$//;
      $no_merged_branches_h->{$branch_name} = 1;
    }
  }
  
  # All branches
  my @cmd = $self->cmd($user, $project, 'branch');
  open my $fh, '-|', @cmd or return;
  my $branches = [];
  while (my $branch_name = $self->_dec(scalar <$fh>)) {
    
    my $branch = $self->branch($user, $project, $branch_name);
    $branch->{no_merged} = 1 if $no_merged_branches_h->{$branch_name};

    push @$branches, $branch;
  }
  
  @$branches = sort { $a->{commit}{age} <=> $b->{commit}{age} } @$branches;
  
  return $branches;
}

sub branch {
  my ($self, $user, $project, $branch_name) = @_;

  $branch_name =~ s/^\*//;
  $branch_name =~ s/^\s*//;
  $branch_name =~ s/\s*$//;
  
  my $branch = {};
  $branch->{name} = $branch_name;
  my $commit = $self->get_commit($user, $project, $branch_name);
  $branch->{commit} = $commit;

  return $branch;
}

sub branches_count {
  my ($self, $user, $project) = @_;
  
  my @cmd = $self->cmd($user, $project, 'branch');
  open my $fh, '-|', @cmd or return;
  my @branches = <$fh>;
  my $branches_count = @branches;
  
  return $branches_count;
}

sub id_by_path {
  my ($self, $user, $project, $rev, $path, $type) = @_;
  
  # Get blob id or tree id (command "git ls-tree")
  $path =~ s#/+$##;
  my @cmd = $self->cmd(
    $user,
    $project,
    'ls-tree',
    $rev,
    '--',
    $path
  );
  open my $fh, '-|', @cmd
    or croak 'Open git-ls-tree failed';
  my $line = $self->_dec(scalar <$fh>);
  close $fh or return;
  my ($t, $id) = ($line || '') =~ m/^[0-9]+ (.+) ([0-9a-fA-F]{40})\t/;
  return if defined $type && $type ne $t;

  return $id;
}


sub last_activity {
  my ($self, $user, $project) = @_;
  
  # Command "git for-each-ref"
  my @cmd = $self->cmd(
    $user,
    $project,
    'for-each-ref',
    '--format=%(committer)',
    '--sort=-committerdate',
    '--count=1', 'refs/heads'
  );
  open my $fh, '-|', @cmd or return;
  my $most_recent = $self->_dec(scalar <$fh>);
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
  
  my @cmd = $self->cmd($user, $project, 'branch', '--no-merged');
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
  my @cmd = $self->cmd($user, $project, 'ls-tree', '-r', '-t', '-z', $base);
  open my $fh, '-|', @cmd or return;

  # Get path
  local $/ = "\0";
  while (my $line = <$fh>) {
    chomp $line;
    $line = $self->_dec($line);

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
  my @cmd = $self->cmd(
    $user,
    $project,
    'show-ref',
    '--dereference'
  );
  open my $fh, '-|', @cmd
    or return;
  my $refs = [];
  while (my $line = $self->_dec(scalar <$fh>)) {
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
  my ($self, $user, $project, $cid) = @_;
  
  # Get object type
  my @cmd = $self->cmd(
    $user,
    $project,
    'cat-file',
    '-t',
    $cid
  );
  open my $fh, '-|', @cmd  or return;
  my $type = $self->_dec(scalar <$fh>);
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
  my @urls = map { chomp; $self->_dec($_) } <$fh>;
  close $fh;

  return \@urls;
}

sub projects {
  my ($self, $user, $opts) = @_;
  
  my $home = $self->rep_home;
  my $dir = "$home/$user";
  
  # Repositories
  opendir my $dh, $self->_enc($dir)
    or croak qq/Can't open directory $dir: $!/;
  my @reps;
  while (my $rep_name = readdir $dh) {
    next unless $rep_name =~ /\.git$/;
    my $project = $rep_name;
    $project =~ s/\.git$//;
    my $rep_path = "$home/$user/$rep_name";
    my @activity = $self->last_activity($user, $project);
    
    my $rep = {};
    $rep->{name} = $project;
    if (@activity) {
      $rep->{age} = $activity[0];
      $rep->{age_string} = $activity[1];
    }
    else { $rep->{age} = 0 }
    
    my $description = $self->description($user, $project) || '';
    $rep->{description} = $self->_chop_str($description, 25, 5);
    
    push @reps, $rep;
  }
  
  return \@reps;
}

sub references {
  my ($self, $user, $project, $type) = @_;
  
  $type ||= '';
  
  # Branches or tags
  my @cmd = $self->cmd(
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
  while (my $line = $self->_dec(scalar <$fh>)) {
    chomp $line;
    if ($line =~ m!^([0-9a-fA-F]{40})\srefs/$type_re/(.*)$!) {
      if (defined $refs{$1}) { push @{$refs{$1}}, $2 }
      else { $refs{$1} = [$2] }
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
  my @cmd = $self->cmd(
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
  my @cmd = $self->cmd(
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
  while (my $line = $self->_dec(scalar <$fh>)) {
    
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
  my ($self, $cid, $key, $value) = @_;

  if (!exists $cid->{$key}) { $cid->{$key} = $value }
  elsif (!ref $cid->{$key}) { $cid->{$key} = [ $cid->{$key}, $value ] }
  else { push @{$cid->{$key}}, $value }
}

sub last_change_commit {
  my ($self, $user, $project, $rev, $file) = @_;
  
  my $commit_log = {};
  $file = '' unless defined $file;
  
  my @cmd = $self->cmd(
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
  my $commit_log_text = $self->_dec(scalar <$fh>);
  
  my $commit;
  if ($commit_log_text =~ /^([0-9a-zA-Z]+)/) {
    my $rev = $1;
    $commit = $self->get_commit($user, $project, $rev);
  }
  
  return $commit;
}

sub parse_blob_diff_lines {
  my ($self, $lines) = @_;
  
  # Parse
  my @lines;
  my $next_before_line_num;
  my $next_after_line_num;
  for my $line (@$lines) {
    chomp $line;
    
    my $class;
    my $before_line_num;
    my $after_line_num;
    
    if ($line =~ /^@@\s-(\d+),\d+\s\+(\d+),\d+/) {
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
    }
    elsif ($line =~ /^\+/) {
      $class = 'to_file';
      $before_line_num = '';
      $after_line_num = $next_after_line_num++;
    }
    elsif ($line =~ /^Binary files/) { $class = 'binary_file' }
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
  
  return \@lines;
}

sub get_commit {
  my ($self, $user, $project, $id) = @_;
  
  # Git rev-list
  my @cmd = $self->cmd(
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
  my $content = $self->_dec(scalar <$fh>);
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
  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday) = gmtime($commit{committer_epoch});
  $commit{age_string_date} = sprintf '%4d-%02d-%02d', 1900 + $year, $mon + 1, $mday;
  $commit{age_string_datetime} = sprintf '%4d-%02d-%02d %02d:%02d:%02d',
    1900 + $year, $mon + 1, $mday, $hour, $min, $sec;
  
  return \%commit;
}

sub get_commits {
  my ($self, $user, $project, $cid, $maxcount, $skip, $file, @args) = @_;

  # Get Commits
  $maxcount ||= 1;
  $skip ||= 0;
  my @cmd = $self->cmd(
    $user,
    $project,
    'rev-list',
    '--header',
    @args,
    ('--max-count=' . $maxcount),
    ('--skip=' . $skip),
    $cid,
    '--',
    (defined $file && length $file ? ($file) : ())
  );
  open my $fh, '-|', @cmd
    or croak 'Open git-rev-list failed';
  
  # Prase Commits text
  local $/ = "\0";
  my @commits;
  while (my $line = $self->_dec(scalar <$fh>)) {
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

  return $self->parse_diff_tree_raw_line($line);
}

sub parse_diff_tree_raw_line {
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
  my @cmd = $self->cmd(
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

  if ($age >= 60 * 60 * 24 * 365) {
    $age_str = (int $age/60/60/24/365);
    $age_str .= ' years ago';
  } elsif ($age >= 60 * 60 * 24 * (365/12)) {
    $age_str = int $age/60/60/24/(365/12);
    $age_str .= ' months ago';
  } elsif ($age >= 60 * 60 * 24 * 7) {
    $age_str = int $age/60/60/24/7;
    $age_str .= ' weeks ago';
  } elsif ($age >= 60 * 60 * 24) {
    $age_str = int $age/60/60/24;
    $age_str .= ' days ago';
  } elsif ($age >= 60 * 60) {
    $age_str = int $age / 60 / 60;
    $age_str .= ' hours ago';
  } elsif ($age >= 60) {
    $age_str = int $age/60;
    $age_str .= ' min ago';
  } elsif ($age >= 1) {
    $age_str = int $age;
    $age_str .= ' sec ago';
  } else {
    $age_str .= ' right now';
  }
  
  $age_str =~ s/^1 /a /;
  
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
    $tid = $self->id_by_path($user, $project, $rev, $dir, 'tree');
  }
  else {
    my $commit = $self->get_commit($user, $project, $rev);
    $tid = $commit->{tree};
  }
  my @entries = ();
  my $show_sizes = 0;
  my @cmd = $self->cmd(
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
    @entries = map { chomp; $self->_dec($_) } <$fh>;
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

sub _dec {
  my ($self, $str) = @_;
  
  my $enc = $self->encoding;
  
  my $new_str;
  eval { $new_str = decode($enc, $str) };
  
  return $@ ? $str : $new_str;
}

sub _enc {
  my ($self, $str) = @_;
  
  my $enc = $self->encoding;
  
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
  my $content = do { local $/; $self->_dec(scalar <$fh>) };
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
