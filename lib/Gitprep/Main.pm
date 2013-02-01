package Gitprep::Main;
use Mojo::Base 'Mojolicious::Controller';
use File::Basename 'dirname';
use Carp 'croak';
use Gitprep::API;

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

sub _quote_command {
  my $self = shift;
  return join(' ',
    map { my $a = $_; $a =~ s/(['!])/'\\$1'/g; "'$a'" } @_ );
}

1;
