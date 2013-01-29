package Gitprep::Main;
use Mojo::Base 'Mojolicious::Controller';
use File::Basename 'dirname';
use Carp 'croak';
use Gitprep::API;

sub blobdiff {
  my $self = shift;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $diff = $self->param('diff');
  my $file = $self->param('file');
  my $from_file = $self->param('from-file');
  $from_file = $file unless defined $from_file;
  my $plain = $self->param('plain');
  my $from_id;
  my $id;
  if ($diff =~ /\.\./) { ($from_id, $id) = $diff =~ /(.+)\.\.(.+)/ }
  else { $id = $diff }
  
  # Git
  my $git = $self->app->git;

  # Get blob diff (command "git diff")
  open my $fh, '-|', $git->cmd($project), 'diff', '-r', '-M', '-p',
      $from_id, $id, '--', $from_file, $file
    or croak "Open git-diff-tree failed";
  
  # Blob diff plain
  if ($plain) {
    # Content
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Render
    my $content_disposition .= "inline; filename=$file";
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type("text/plain; charset=" . $git->encoding);
    $self->render(data => $content);
  }
  
  # Blob diff
  else {
    # Lines
    my @lines = map { $git->dec($_) } <$fh>;
    close $fh;
    my $lines = $self->_parse_blobdiff_lines(\@lines);
    
    # Commit
    my $commit = $git->parse_commit($project, $id);
    
    # Render
    $self->render(
      '/blobdiff',
      home => $home,
      home_ns => $home_ns,
      project => $project,
      project_ns => $project_ns,
      id => $id,
      from_id => $from_id,
      file => $file,
      from_file => $from_file,
      commit => $commit,
      lines => $lines
    );
  }
}

sub commitdiff {
  my $self = shift;
  
  # Paramters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $diff = $self->param('diff');
  my ($from_id, $id) = $diff =~ /(.+)\.\.(.+)/;
  $id = $diff unless defined $id;
  
  # Git
  my $git = $self->app->git;
  
  # Commit
  my $commit = $git->parse_commit($project, $id)
    or croak 'Unknown commit object';
  my $author_date
    = $git->parse_date($commit->{author_epoch}, $commit->{author_tz});
  my $committer_date
    = $git->parse_date($commit->{committer_epoch}, $commit->{committer_tz});
  $commit->{author_date} = $git->timestamp($author_date);
  $commit->{committer_date} = $git->timestamp($committer_date);
  $from_id = $commit->{parent} unless defined $from_id;
  
  # Plain text
  if ($self->param('plain')) {
    # Get blob diffs (command "git diff-tree")
    my @cmd = ($git->cmd($project), 'diff-tree', '-r', '-M',
        '-p', $from_id, $id, '--');
    open my $fh, '-|', @cmd
      or croak 'Open git-diff-tree failed';

    # Content
    my $content = do { local $/; <$fh> };
    my $content_disposition .= "inline; filename=$id";
    
    # Render
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type("text/plain;charset=" . $git->encoding);
    $self->render_data($content);
  }
  
  # HTML
  else {
    
    # Diff tree
    my $difftrees = $git->difftree($project,
      $id, $commit->{parent}, $commit->{parents});
    
    # Get blob diffs (command "git diff-tree")
    my @cmd = ($git->cmd($project), 'diff-tree', '-r', '-M',
      '--no-commit-id', '--patch-with-raw', $from_id, $id, '--');
    open my $fh, '-|', @cmd
      or croak 'Open git-diff-tree failed';

    # Parse output
    my @blobdiffs;
    while (my $line = $git->dec(scalar <$fh>)) {
      
      # Parse line
      chomp $line;
      my $diffinfo = $git->parse_difftree_raw_line($line);
      my $from_file = $diffinfo->{from_file};
      my $file = $diffinfo->{to_file};
      
      # Get blobdiff (command "git diff-tree")
      my @cmd = ($git->cmd($project), 'diff-tree', '-r', '-M', '-p',
        $from_id, $id, '--', (defined $from_file ? $from_file : ()), $file);
      open my $fh_blobdiff, '-|', @cmd
        or croak 'Open git-diff-tree failed';
      my @lines = map { $git->dec($_) } <$fh>;
      close $fh_blobdiff;
      my $blobdiff = {
        file => $file,
        from_file => $from_file,
        lines => $self->_parse_blobdiff_lines(\@lines)
      };
      
      # Status
      for my $difftree (@$difftrees) {
        if ($difftree->{to_file} eq $file) {
          $blobdiff->{status} = $difftree->{status};
          last;
        }
      }
      
      push @blobdiffs, $blobdiff;
    }

    # References
    my $refs = $git->references($project);
    
    # Render
    $self->render(
      'commitdiff',
      home => $home,
      home_ns => $home_ns,
      project => $project,
      project_ns => $project_ns,
      from_id => $from_id,
      id => $id,
      commit => $commit,
      difftrees => $difftrees,
      blobdiffs => \@blobdiffs,
      refs => $refs
    );
  }
}

sub _root_ns {
  my $self = shift;
  
  my $root = $self->root;
  $root =~ s/^\///;
  
  return $root;
}

sub snapshot {
  my $self = shift;

  # Parameter
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  
  # Git
  my $git = $self->app->git;

  # Object type
  my $type = $git->object_type($project, "$id^{}");
  if (!$type) { croak 404, 'Object does not exist' }
  elsif ($type eq 'blob') { croak 400, 'Object is not a tree-ish' }
  
  my ($name, $prefix) = $git->snapshot_name($project, $id);
  my $file = "$name.tar.gz";
  my $cmd = $self->_quote_command(
    $git->cmd($project), 'archive', "--format=tar", "--prefix=$prefix/", $id
  );
  $cmd .= ' | ' . $self->_quote_command('gzip', '-n');

  $file =~ s/(["\\])/\\$1/g;

  open my $fh, '-|', $cmd
    or croak 'Execute git-archive failed';
  
  # Write chunk
  $self->res->headers->content_type('application/x-tar');
  $self->res->headers->content_disposition(qq/attachment; filename="$file"/);
  my $cb;
  $cb = sub {
    my $c = shift;
    my $size = 500 * 1024;
    my $length = sysread($fh, my $buffer, $size);
    unless (defined $length) {
      close $fh;
      undef $cb;
      return;
    }
    $c->write_chunk($buffer, $cb);
  };
  $self->$cb;
}

sub tag {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $tag  = $git->parse_tag($project, $id);
  my $author_date
    = $git->parse_date($tag->{author_epoch}, $tag->{author_tz});
  $tag->{author_date} = $git->timestamp($author_date);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    tag => $tag,
  );
}

sub _parse_blobdiff_lines {
  my ($self, $lines_raw) = @_;
  
  # Git
  my $git = $self->app->git;
  
  # Parse
  my @lines;
  for my $line (@$lines_raw) {
    $line = $git->dec($line);
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

sub _parse_id_path {
  my ($self, $project, $id_path) = @_;
  
  # Git
  my $git = $self->app->git;
  
  # Parse id and path
  my $refs = $git->references($project);
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

sub _quote_command {
  my $self = shift;
  return join(' ',
    map { my $a = $_; $a =~ s/(['!])/'\\$1'/g; "'$a'" } @_ );
}

1;
