package Gitprep::Controller;
use Mojo::Base 'Mojolicious::Controller';

sub raw {
  my $self = shift;
  
  # Parameters
  my $user = $self->param('user');
  my $project = $self->param('project');
  my $rev = $self->param('rev');
  my $file = $self->param('file');

  # Git
  my $git = $self->app->git;

  # Commit
  my $commit_log = $git->latest_commit_log($user, $project, $rev, $file);
  
  # Blob raw
  my $blob_raw = $git->blob_raw($user, $project, $rev, $file);
  
  # Content type
  my $type = $git->blob_contenttype($user, $project, $rev, $file);

  # Convert text/* content type to text/plain
  if ($self->app->config->{basic}{prevent_xss} &&
    ($type =~ m#^text/[a-z]+\b(.*)$# ||
    ($type =~ m#^[a-z]+/[a-z]\+xml\b(.*)$#)))
  {
    my $rest = $1;
    $rest = defined $rest ? $rest : '';
    $type = "text/plain$rest";
  }

  # File name
  my $file_name = $rev;
  if (defined $file) { $file_name = $file }
  elsif ($type =~ m/^text\//) { $file_name .= '.txt' }
  
  # Content disposition
  my $sandbox = $self->app->config->{basic}{prevent_xss} &&
    $type !~ m#^(?:text/[a-z]+|image/(?:gif|png|jpeg))(?:[ ;]|$)#;
  my $content_disposition = $sandbox ? 'attachment' : 'inline';
  $content_disposition .= "; filename=$file_name";
  
  # Response
  $self->res->headers->content_disposition($content_disposition);
  $self->res->headers->content_type($type);
  
  $self->render(data => $blob_raw);
}

1;

