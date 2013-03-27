package Gitprep::RepManager;
use Mojo::Base -base;

use Carp 'croak';
use File::Copy 'move';

has 'app';

sub rename_project {
  my ($self, $user, $project, $renamed_project) = @_;
  
  my $git = $self->app->git;
  my $dbi = $self->app->dbi;
  
  my $error = {};
  
  if ($self->_exists_project($user, $renamed_project)
    || $self->_exists_rep($user, $renamed_project))
  {
    $error->{message} = 'Already exists';
    return $error;
  }
  else {
    $dbi->connector->txn(sub {
      $self->_rename_project($user, $project, $renamed_project);
      $self->_rename_rep($user, $project, $renamed_project);
    });
    if ($@) {
      $error->{message} = 'Rename failed';
      return $error;
    }
  }
  
  return 1;
}

sub _exists_project {
  my ($self, $user, $project) = @_;

  my $dbi = $self->app->dbi;
  my $row = $dbi->model('project')->select(id => [$user, $project])->one;
  
  return $row ? 1 : 0;
}

sub _exists_rep {
  my ($self, $user, $project) = @_;
  
  my $rep = $self->app->git->rep($user, $project);
  
  return -e $rep;
}

sub _rename_project {
  my ($self, $user, $project, $renamed_project) = @_;
  
  my $dbi = $self->app->dbi;
  
  croak "Invalid parameters"
    unless defined $user && defined $project && defined $renamed_project;
  
  $dbi->model('project')->update({name => $renamed_project}, id => [$user, $project]);
}

sub _rename_rep {
  my ($self, $user, $project, $renamed_project) = @_;
  
  croak "Invalid user name or project"
    unless defined $user && defined $project && defined $renamed_project;
  my $rep = $self->app->git->rep($user, $project);
  my $renamed_rep = $self->app->git->rep($user, $renamed_project);
  
  move($rep, $renamed_rep)
    or croak "Can't move $rep to $renamed_rep: $!";
}

1;
