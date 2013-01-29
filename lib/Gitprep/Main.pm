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

sub _quote_command {
  my $self = shift;
  return join(' ',
    map { my $a = $_; $a =~ s/(['!])/'\\$1'/g; "'$a'" } @_ );
}

1;
