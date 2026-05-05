package Gitprep::Repository;

use strict;
use warnings;

use Gitprep::Repository::Wiki;
use Gitprep::Repository::Work;

my $home;

use constant _project_suffix => '';
use constant _url_suffix => '';

# Create a new repository information object.
# If called via an existing object, the user and project default to the latter.
sub new {
  my ($self, $user, $project) = @_;

  if (ref($self)) {
    $user //= $self->user;
    $project //= $self->project;
    $self = ref($self);
  }
  return bless {
    user => $user,
    project => $project
  }, $self;
}

# Return the repository owner.
sub user { return shift->{user}; }

# Return the repository project name.
sub project { return shift->{project}; }

# Return wether the repository is a wiki.
sub is_wiki { return shift->isa('Gitprep::Repository::Wiki')? 1: 0; }

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

# Return the repository's top level directory.
sub root {
  my ($self, $file) = @_;
  my $home = $self->home;
  my $wiki = $self->_project_suffix;
  return $self->_path("$home/$self->{user}/$self->{project}$wiki.git", $file);
}

# Return the repository's directory where git support files are located.
sub git_dir { return shift->root(@_); }

# Return the url for the repository.
sub url {
  my ($self, $file) = @_;
  my $wiki = $self->_url_suffix;
  return $self->_path("/$self->{user}/$self->{project}$wiki", $file);
}

# Return a suitable unambiguous name for an upstream repository.
sub remote_name {
  my $self = shift;
  my $wiki = $self->_project_suffix;
  return "repo/$self->{user}/$self->{project}$wiki";
}

# Return a bare repository matching the object, whatever variant is the latter.
sub repo {
  my $self = shift;
  return Gitprep::Repository->new($self->user, $self->project);
}

# Return a wiki repository matching the object, whatever variant is the latter.
sub wiki {
  my $self = shift;
  return Gitprep::Repository::Wiki->new($self->user, $self->project);
}

# Return a work repository whose origin is the object.
sub work { return Gitprep::Repository::Work->new(@_); }

# Create a new repository information object, taking the project name into
#  account to determine if this is a wiki or not.
sub maybe_wiki {
  my $rep_info = shift->new(@_);
  unless ($rep_info->is_wiki) {
    $rep_info->project =~ /^(.*?)(\.wiki)?$/;
    $rep_info = Gitprep::Repository::Wiki->new($rep_info->user, $1) if $2;
  }
  return $rep_info;
}

# Protected method to cleanly concatenate paths.
sub _path {
  my ($self, $path, $file) = @_;
  $file //= '';
  $file =~ s#^/*(.*?)/*$#$1#;
  $file =~ s#/+$#/#g;
  $path .= "/$file" if $file ne '';
  return $path;
}


1;
