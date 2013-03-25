package Gitprep::RepManager;
use Mojo::Base -base;

has 'c';

sub rename_project {
  my ($self, $user, $project, $renamed_project) = @_;
  
  my $c = $self->c;
  my $api = $c->gitprep_api($c);
  my $git = $c->app->git;
  my $dbi = $c->app->dbi;
  
  my $error = {};
  
  if ($api->exists_project($user, $renamed_project)
    || $git->exists_project($user, $renamed_project))
  {
    $error->{message} = 'Already exists';
    return $error;
  }
  else {
      $dbi->connector->txn(sub {
        $api->rename_project($user, $project, $renamed_project);
        $git->rename_project($user, $project, $renamed_project);
      });
    if ($@) {
      $error->{message} = 'Rename failed';
      return $error;
    }
  }
  
  return 1;
}

1;
