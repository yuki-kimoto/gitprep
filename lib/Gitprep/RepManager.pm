package Gitprep::RepManager;
use Mojo::Base -base;

use Carp 'croak';
use File::Copy 'move';
use File::Path qw/mkpath rmtree/;
use Mojo::JSON;
use File::Temp ();

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

sub exists_project { shift->_exists_project(@_) }

sub fork_project {
  my ($self, $login_user, $user, $project) = @_;
  
  my $dbi = $self->app->dbi;
  
  my $error;
  eval {
    $dbi->connector->txn(sub {
      
      # Create project
      eval {
        $self->_create_project(
          $login_user,
          $project,
          {
            forked_user => $user,
            forked_project => $project
          }
        );
      };
      croak $error = $@ if $@;
      
      # Create repository
      eval {
        $self->_fork_rep($user, $project, $login_user, $project);
      };
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
}

sub _fork_rep {
  my ($self, $user, $project, $to_user, $to_project) = @_;
  
  # Git
  my $git = $self->app->git;
  
  # Create working directory
  my $temp_dir =  File::Temp->newdir;
  my $temp_rep = "$temp_dir/temp.git";
  
  my $rep = $git->rep($user, $project);
  
  my @git_clone_cmd = (
    $git->bin,
    'clone',
    '-q',
    '--bare',
    $rep,
    $temp_rep
  );
  system(@git_clone_cmd) == 0
    or croak "Can't execute git clone";
  
  # Move temp rep to rep
  my $to_rep = $git->rep($to_user, $to_project);
  move $temp_rep, $to_rep
    or croak "Can't move $temp_rep to $rep: $!";
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

sub _create_project {
  my ($self, $user, $project, $opts) = @_;
  $opts ||= {};
  
  # Config
  my $config = {default_branch => 'master'};
  my $config_json = Mojo::JSON->new->encode($config);
  
  # Create project
  $self->app->dbi->model('project')->insert(
    {config => $config_json},
    id => [$user, $project]
  );
}

sub _create_rep {
  my ($self, $user, $project, $opts) = @_;
  
  # Git
  my $git = $self->app->git;
  
  # Create temp repository
  my $temp_dir =  File::Temp->newdir;
  my $temp_rep = "$temp_dir/remote.git";
  mkdir $temp_rep
    or croak "Can't create directory $temp_rep: $!";
  
  # Git init
  {
    my @git_init_cmd = $git->cmd_rep($temp_rep, 'init', '--bare');
    open my $fh, "-|", @git_init_cmd
      or croak  "Can't execute git init";
    close $fh;
  }
  
  # Add git-daemon-export-ok
  {
    my $file = "$temp_rep/git-daemon-export-ok";
    open my $fh, '>', $file
      or croak "Can't create git-daemon-export-ok: $!"
  }
  
  # HTTP support
  my @git_update_server_info_cmd = $git->cmd_rep(
    $temp_rep,
    '--bare',
    'update-server-info'
  );
  system(@git_update_server_info_cmd) == 0
    or croak "Can't execute git --bare update-server-info";
  move("$temp_rep/hooks/post-update.sample", "$temp_rep/hooks/post-update")
    or croak "Can't move post-update";
  
  # Description
  if (my $description = $opts->{description}) {
    my $file = "$temp_rep/description";
    open my $fh, '>', $file
      or croak "Can't open $file: $!";
    print $fh $description
      or croak "Can't write $file: $!";
    close $fh;
  }
  
  # Add README and commit
  if ($opts->{readme}) {
    # Create working directory
    my $temp_dir =  File::Temp->newdir;
    my $temp_work = "$temp_dir/work";
    mkdir $temp_work
      or croak "Can't create directory $temp_work: $!";

    # Git init
    my @git_init_cmd = $git->cmd_rep($temp_work, 'init', '-q');
    system(@git_init_cmd) == 0
      or croak "Can't execute git init";
    
    # Add README
    my $file = "$temp_work/README";
    open my $fh, '>', $file
      or croak "Can't create $file: $!";
    my @git_add_cmd = $git->cmd_rep(
      $temp_work,
      "--work-tree=$temp_work",
      'add',
      'README'
    );
    system(@git_add_cmd) == 0
      or croak "Can't execute git add";
    
    # Commit
    my @git_commit_cmd = $git->cmd_rep(
      $temp_work,
      "--work-tree=$temp_work",
      'commit',
      '-q',
      '-m',
      'first commit'
    );
    system(@git_commit_cmd) == 0
      or croak "Can't execute git commit";
    
    # Push
    {
      my @git_push_cmd = $git->cmd_rep(
        $temp_work,
        "--work-tree=$temp_work",
        'push',
        '-q',
        $temp_rep,
        'master'
      );
      # (This is bad, but --quiet option can't supress in old git)
      my $git_push_cmd = join(' ', @git_push_cmd);
      system("$git_push_cmd 2> /dev/null") == 0
        or croak "Can't execute git push";
    }
  }
  
  # Move temp rep to rep
  my $rep = $git->rep($user, $project);
  move $temp_rep, $rep
    or croak "Can't move $temp_rep to $rep: $!";
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
