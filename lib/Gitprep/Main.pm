package Gitprep::Main;
use Mojo::Base 'Mojolicious::Controller';
use File::Basename 'dirname';
use Carp 'croak';
use Gitprep::API;

sub archive {
  my $self = shift;
  
  # API
  my $api = Gitprep::API->new($self);

  # Parameter
  my $user = $self->param('user');
  my $project = $self->param('project');
  my $root_ns = $api->root_ns($self->config->{root});
  my $rep_ns = "$root_ns/$user/$project.git";
  my $rep = "/$rep_ns";
  my $rev = $self->param('rev');
  my $archive_type = $self->stash('archive_type');
  my $content_type;
  my $format;
  my $ext;
  if ($archive_type eq 'tar') {
    $format = 'tar';
    $ext = 'tar.gz';
    $content_type = 'application/x-tar';
  }
  elsif ($archive_type eq 'zip') {
    $format = 'zip';
    $ext = 'zip';
    $content_type = 'application/zip';
  }
  
  # Git
  my $git = $self->app->git;

  # Object type
  my $type = $git->object_type($rep, "$rev^{}");
  if (!$type) { croak 404, 'Object does not exist' }
  elsif ($type eq 'blob') { croak 400, 'Object is not a tree-ish' }
  
  my $name = "$project-$rev";
  my $file = "$name.$ext";
  
  my $cmd = $self->_quote_command(
    $git->cmd($rep), 'archive', "--format=$format", "--prefix=$name/", $rev
  );
  if ($archive_type eq 'tar') {
    $cmd .= ' | ' . $self->_quote_command('gzip', '-n');
  }
  $file =~ s/(["\\])/\\$1/g;

  open my $fh, '-|', $cmd
    or croak 'Execute git-archive failed';
  
  # Write chunk
  $self->res->headers->content_type($content_type);
  $self->res->headers->content_disposition(qq/attachment; filename="$file"/);
  my $cb;
  $cb = sub {
    my $c = shift;
    my $size = 500 * 1024;
    my $length = sysread($fh, my $buffer, $size);
    unless ($length) {
      close $fh;
      undef $cb;
      $c->finish;
      return;
    }
    $c->write_chunk($buffer, $cb);
  };
  $self->$cb;
}

sub _quote_command {
  my $self = shift;
  return join(' ',
    map { my $a = $_; $a =~ s/(['!])/'\\$1'/g; "'$a'" } @_ );
}

1;
