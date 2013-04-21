package Gitprep::RepManager;
use Mojo::Base -base;

use Carp 'croak';
use File::Copy 'move';
use File::Path qw/mkpath rmtree/;
use File::Temp ();
use Encode 'encode';

has 'app';

sub default_branch {
  my ($self, $user, $project) = @_;
  
  my $default_branch = $self->app->dbi->model('project')
    ->select('default_branch', id => [$user, $project])
    ->value;
  
  return $default_branch;
}

sub members {
  my ($self, $user, $project) = @_;
  
  # DBI
  my $dbi = $self->app->dbi;
  
  # Original project id
  my $original_pid = $dbi->model('project')
    ->select('original_pid', id => [$user, $project])->value;
  
  # Members
  my $members = $dbi->model('project')->select(
    ['user_id as id', 'name as project'],
    where => [
      ['and',
        ':original_pid{=}',
        ['or', ':user_id{<>}', ':name{<>}']
      ],
      {
        original_pid => $original_pid,
        user_id => $user,
        name => $project
      }
    ],
    append => 'order by user_id, name'
  )->all;
  
  warn $dbi->last_sql;
  use D;d $members;

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
  my ($self, $user, $original_user, $project) = @_;
  
  # DBI
  my $dbi = $self->app->dbi;
  
  # Fork project
  my $error;
  eval {
    $dbi->connector->txn(sub {
      
      # Original project id
      my $original_pid = $dbi->model('project')
        ->select('original_pid', id => [$original_user, $project])->value;
      
      croak "Can't get original project id"
        unless defined $original_pid && $original_pid > 0;
      
      # Create project
      eval {
        $self->_create_project(
          $user,
          $project,
          {
            original_user => $original_user,
            original_project => $project,
            original_pid => $original_pid
          }
        );
      };
      croak $error = $@ if $@;
      
      # Create repository
      eval {
        $self->_fork_rep($original_user, $project, $user, $project);
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
  
  # Git clone
  my $rep = $git->rep($user, $project);
  my $to_rep = $git->rep($to_user, $to_project);
  my @git_clone_cmd = (
    $git->bin,
    'clone',
    '-q',
    '--bare',
    $rep,
    $to_rep
  );
  system(@git_clone_cmd) == 0
    or croak "Can't execute git clone";
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
    "original_project not null default ''",
    "original_pid integer not null default 0"
  ];
  for my $column (@$project_columns) {
    eval { $dbi->execute("alter table project add column $column") };
  }

  # Check project table
  eval { $dbi->select([qw/default_branch original_user original_project original_pid/], table => 'project') };
  if ($@) {
    my $error = "Can't create project table properly: $@";
    $self->app->log->error($error);
    croak $error;
  }

  # Create number table
  eval {
    my $sql = <<"EOS";
create table number (
  row_id integer primary key autoincrement,
  key not null unique
);
EOS
    $dbi->execute($sql);
  };
  
  # Create number columns
  my $number_columns = [
    "value integer not null default '0'"
  ];
  for my $column (@$number_columns) {
    eval { $dbi->execute("alter table number add column $column") };
  }

  # Check number table
  eval { $dbi->select([qw/row_id key value/], table => 'number') };
  if ($@) {
    my $error = "Can't create number table properly: $@";
    $self->app->log->error($error);
    croak $error;
  }
  
  # Original project id numbert
  eval { $dbi->insert({key => 'original_pid'}, table => 'number') };
  my $original_pid = $dbi->select(
    'key',
    table => 'number',
    where => {key => 'original_pid'}
  )->value;
  unless (defined $original_pid) {
    my $error = "Can't create original_pid row in number table";
    $self->app->log->error($error);
    croak $error;
  }
}

sub _create_project {
  my ($self, $user, $project, $params) = @_;
  $params ||= {};
  
  # DBI
  my $dbi = $self->app->dbi;
  
  # Create project
  $dbi->connector->txn(sub {
    unless (defined $params->{original_pid}) {
      my $number = $dbi->model('number')->select('value', where => {key => 'original_pid'})->value;
      $number++;
      $dbi->model('number')->update({value => $number}, where => {key => 'original_pid'});
      $params->{original_pid} = $number;
    }
    $dbi->model('project')->insert($params, id => [$user, $project]);
  });
}

sub _create_rep {
  my ($self, $user, $project, $opts) = @_;
  
  # Git
  my $git = $self->app->git;
  
  # Create repository directory
  my $rep = $git->rep($user, $project);
  mkdir $rep
    or croak "Can't create directory $rep: $!";

  eval {
    # Git init
    {
      my @git_init_cmd = $git->cmd_rep($rep, 'init', '--bare');
      open my $fh, "-|", @git_init_cmd
        or croak  "Can't execute git init";
      close $fh;
    }
    
    # Add git-daemon-export-ok
    {
      my $file = "$rep/git-daemon-export-ok";
      open my $fh, '>', $file
        or croak "Can't create git-daemon-export-ok: $!"
    }
    
    # HTTP support
    my @git_update_server_info_cmd = $git->cmd_rep(
      $rep,
      '--bare',
      'update-server-info'
    );
    system(@git_update_server_info_cmd) == 0
      or croak "Can't execute git --bare update-server-info";
    move("$rep/hooks/post-update.sample", "$rep/hooks/post-update")
      or croak "Can't move post-update";
    
    # Description
    {
      my $description = $opts->{description};
      $description = '' unless defined $description;
      my $file = "$rep/description";
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
          $rep,
          'master'
        );
        # (This is bad, but --quiet option can't supress in old git)
        my $git_push_cmd = join(' ', @git_push_cmd);
        system("$git_push_cmd 2> /dev/null") == 0
          or croak "Can't execute git push";
      }
    }
  };
  if ($@) {
    rmtree $rep;
    croak $@;
  }
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
