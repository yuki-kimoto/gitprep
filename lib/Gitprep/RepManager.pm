package Gitprep::RepManager;
use Mojo::Base -base;

use Carp 'croak';
use File::Copy 'move';
use File::Path qw/mkpath rmtree/;
use File::Temp ();
use Encode 'encode';

has 'app';

sub members {
  my ($self, $user, $project_name) = @_;
  
  # DBI
  my $dbi = $self->app->dbi;
  
  # Projects
  my $projects = $self->app->dbi
    ->model('project')
    ->select([qw/user_id name original_user original_project/])
    ->all;
  
  # Members
  my $members = [];
  for my $project (@$projects) {
    $project->{original_user} = ''
      unless defined $project->{original_user};
    
    $project->{original_project} = ''
      unless defined $project->{original_project};
    
    push @$members, {id => $project->{user_id}, project => $project->{name}}
      if $project->{original_user} eq $user
        && $project->{original_project} eq $project_name;
  }

  return $members;
}

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
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
}

sub create_user {
  my ($self, $user, $data) = @_;

  my $dbi = $self->app->dbi;
  
  # Create user
  my $error;
  eval {
    $dbi->connector->txn(sub {
      eval { $self->_create_db_user($user, $data) };
      croak $error = $@ if $@;
      eval {$self->_create_user_dir($user) };
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
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
  
  return 1;
}

sub delete_user {
  my ($self, $user) = @_;
  
  my $dbi = $self->app->dbi;
  
  # Delete user
  my $error;
  eval {
    $dbi->connector->txn(sub {
      eval { $self->_delete_db_user($user) };
      croak $error = $@ if $@;
      eval {$self->_delete_user_dir($user) };
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
  
  return 1;
}

sub original_project {
  my ($self, $user, $project) = @_;
  
  my $dbi = $self->app->dbi;
  
  my $original_project = $dbi->model('project')
    ->select('original_project', id => [$user, $project])
    ->value;
  return unless defined $original_project && length $original_project;
  
  return $original_project;
}

sub original_user {
  my ($self, $user, $project) = @_;
  
  my $dbi = $self->app->dbi;
  
  my $original_user = $dbi->model('project')
    ->select('original_user', id => [$user, $project])
    ->value;
  return unless defined $original_user && length $original_user;
  
  return $original_user;
}

sub _delete_db_user {
  my ($self, $user) = @_;
  
  $self->app->dbi->model('user')->delete(id => $user);
}

sub _delete_user_dir {
  my ($self, $user) = @_;

  my $home = $self->app->git->rep_home;
  my $user_dir = "$home/$user";
  rmtree $user_dir;
}

sub _create_db_user {
  my ($self, $user, $data) = @_;
  
  $self->app->dbi->model('user')->insert($data, id => $user);
}

sub _create_user_dir {
  my ($self, $user) = @_;

  my $home = $self->app->git->rep_home;
  my $user_dir = "$home/$user";
  mkpath $user_dir;
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
            original_user => $user,
            original_project => $project
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
  
  # Add remote branch
  {
    my @git_remote_cmd = $git->cmd(
      $user,
      $project,
      'remote'
    );
    open my $fh, "-|",  @git_remote_cmd
      or croak  "Can't execute git remote";
    
    my $exists;
    while (my $remote = $git->dec(scalar <$fh>)) {
      chomp $remote;
      if ($remote eq $to_user) {
        $exists = 1;
        last;
      }
    }
    close $fh;
    
    unless ($exists) {
      my $rep_home = $git->rep_home;
      my @git_remote_add_cmd = $git->cmd(
        $user,
        $project,
        'remote',
        'add',
        $to_user,
        "file://$rep_home/$to_user/$to_project.git"
      );
      system(@git_remote_add_cmd) == 0
        or croak "Can't execute remote add";
    }
  }

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

sub setup_database {
  my $self = shift;
  
  my $dbi = $self->app->dbi;
  
  # Create user table
  eval {
    my $sql = <<"EOS";
create table user (
  row_id integer primary key autoincrement,
  id not null unique default ''
);
EOS
    $dbi->execute($sql);
  };

  # Create usert columns
  my $user_columns = [
    "admin not null default '0'",
    "password not null default ''",
    "salt not null default ''"
  ];
  for my $column (@$user_columns) {
    eval { $dbi->execute("alter table user add column $column") };
  }
  
  # Check user table
  eval { $dbi->select([qw/row_id id admin password salt/], table => 'user') };
  if ($@) {
    my $error = "Can't create user table properly: $@";
    $self->app->log->error($error);
    croak $error;
  }
  
  # Create project table
  eval {
    my $sql = <<"EOS";
create table project (
  row_id integer primary key autoincrement,
  user_id not null,
  name not null,
  unique(user_id, name)
);
EOS
    $dbi->execute($sql);
  };
  
  # Create Project columns
  my $project_columns = [
    "default_branch not null default 'master'",
    "original_user not null default ''",
    "original_project not null default ''"
  ];
  for my $column (@$project_columns) {
    eval { $dbi->execute("alter table project add column $column") };
  }

  # Check project table
  eval { $dbi->select([qw/default_branch original_user original_project/], table => 'project') };
  if ($@) {
    my $error = "Can't create project table properly: $@";
    $self->app->log->error($error);
    croak $error;
  }
}

sub _create_project {
  my ($self, $user, $project, $params) = @_;
  $params ||= {};
  
  # Create project
  $self->app->dbi->model('project')->insert($params, id => [$user, $project]);
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
    print $fh encode('UTF-8', $description)
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
  
  # Rename project
  $dbi->model('project')->update(
    {name => $renamed_project},
    id => [$user, $project]
  );
  
  # Rename related project
  $dbi->model('project')->update(
    {original_project => $renamed_project},
    where => {original_user => $user, original_project => $project},
  );
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
