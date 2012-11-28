package Gitprep::API;
use Mojo::Base -base;

use Carp ();
use File::Basename ();

sub croak { Carp::croak(@_) }
sub dirname { File::Basename::dirname(@_) }

has 'cntl';

sub new {
  my ($class, $cntl) = @_;

  my $self = $class->SUPER::new(cntl => $cntl);
  
  return $self;
}

sub root_ns {
  my ($self, $root) = @_;

  $root =~ s/^\///;
  
  return $root;
}

sub parse_id_path {
  my ($self, $project, $id_path) = @_;
  
  my $c = $self->cntl;
  
  # Git
  my $git = $c->app->git;
  
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

1;

