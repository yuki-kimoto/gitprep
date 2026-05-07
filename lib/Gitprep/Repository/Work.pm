package Gitprep::Repository::Work;

use strict;
use warnings;

use Gitprep::Repository;

my $home;

# Create a new work repository information object.
sub new {
  my $self = shift;
  my $origin = $_[0];

  unless (ref($origin)) {
    $origin = $self;
    $origin = Gitprep::Repository->new(@_) unless ref($origin);
  }
  $origin = $origin->origin if $origin->isa('Gitprep::Repository::Work');

  return bless {
    origin => $origin
  }, $self;
}

sub origin { return shift->{origin}; }

# Getter/setter for the home property.
# If called for the class, change the default.
sub home {
  my ($self, $home_dir) = @_;

  if (ref($self)) {
    $self->{home} = $home_dir if defined $home_dir;
    return $self->{home} if exists $self->{home};
  }
  $home = $home_dir if defined $home_dir;
  return $home;
}

sub user { return shift->origin->user(@_); }
sub project { return shift->origin->project(@_); }
sub is_wiki { return shift->origin->is_wiki(@_); }
sub repo { return shift->origin->repo(@_); }
sub wiki { return shift->origin->wiki(@_); }
sub work { return shift->new(@_); }

sub root {
  my ($self, $file) = @_;
  my $home = $self->home;
  my $origin = $self->origin;
  my $user = $origin->user;
  my $project = $origin->project;
  my $is_wiki = $origin->_project_suffix;
  my $path = "$home/$user/$project$is_wiki";
  $path = "$path/$file" if defined $file;
  return $path;
}

sub git_dir {
  my ($self, $file) = @_;
  my $root = $self->root;
  my $path = "$root/.git";
  $path = "$path/$file" if defined $file;
  return $path;
}

# Return the top level directory for the project files.
sub work_tree {
  my ($self, $file) = @_;
  return $self->root($file);
}


1;
