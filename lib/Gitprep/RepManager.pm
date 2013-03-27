package Gitprep::RepManager;
use Mojo::Base -base;

use Carp 'croak';
use File::Copy 'move';
use File::Path qw/mkpath rmtree/;
use Mojo::JSON;

has 'app';

sub create_project {
  my ($self, $user, $project, $opts) = @_;
  
  my $dbi = $self->app->dbi;
  
  # Create project
  my $error;
  eval {
    $dbi->connector->txn(sub {
      eval { $self->_create_project($user, $project) };
      croak $error = $@ if $@;
      eval {$self->_create_rep($user, $project, $opts) };
      $error->{message} = $@;
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
}

sub _create_project {
  my ($self, $user, $project) = @_;
  
  my $config = {default_branch => 'master'};
  my $config_json = Mojo::JSON->new->encode($config);
  $self->app->dbi->model('project')->insert(
    {config => $config_json},
    id => [$user, $project]
  );
}

sub _create_rep {
  my ($self, $user, $project, $opts) = @_;
  
  my $git = $self->app->git;

  my $rep_home = $git->rep_home;
  my $rep = "$rep_home/$user/$project.git";
  eval {
    # Repository
    mkpath $rep;
      
    # Git init
    my @git_init_cmd = $git->_cmd($user, $project, 'init', '--bare');
    system(@git_init_cmd) == 0
      or croak "Can't execute git init";
      
    # Add git-daemon-export-ok
    {
      my $file = "$rep/git-daemon-export-ok";
      open my $fh, '>', $file
        or croak "Can't create git-daemon-export-ok: $!"
    }
    
    # HTTP support
    my @git_update_server_info_cmd = $git->_cmd(
      $user,
      $project,
      '--bare',
      'update-server-info'
    );
    system(@git_update_server_info_cmd) == 0
      or croak "Can't execute git --bare update-server-info";
    move("$rep/hooks/post-update.sample", "$rep/hooks/post-update")
      or croak "Can't move post-update";
    
    # Description
    if (my $description = $opts->{description}) {
      my $file = "$rep/description";
      open my $fh, '>', $file
        or croak "Can't open $file: $!";
      print $fh $description
        or croak "Can't write $file: $!";
      close $fh;
    }
  };
  if ($@) {
    my $error = $@;
    eval { $self->_delete_rep($user, $project) };
    croak $error;
  }
}

sub delete_project {
  my ($self, $user, $project) = @_;
  
  my $dbi = $self->app->dbi;
  
  # Delete project
  my $error;
  eval {
    $dbi->connector->txn(sub {
      eval { $self->_delete_project($user, $project) };
      croak $error = $@ if $@;
      eval {$self->_delete_rep($user, $project) };
      $error->{message} = $@;
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
  
  return 1;
}

sub _delete_project {
  my ($self, $user, $project) = @_;
  
  my $dbi = $self->app->dbi;
  $dbi->model('project')->delete(id => [$user, $project]);
}

sub _delete_rep {
  my ($self, $user, $project) = @_;

  my $rep_home = $self->app->git->rep_home;
  croak "Can't remove repository. repositry home is empty"
    if !defined $rep_home || $rep_home eq '';
  my $rep = "$rep_home/$user/$project.git";
  rmtree $rep;
  croak "Can't remove repository. repository is rest"
    if -e $rep;
}

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
