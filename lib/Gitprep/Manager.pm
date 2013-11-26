package Gitprep::Manager;
use Mojo::Base -base;

use Carp 'croak';
use Encode 'encode';
use File::Copy qw/move copy/;
use File::Path qw/mkpath rmtree/;
use File::Temp ();

has 'app';

sub admin_user {
  my $self = shift;
  
  # Admin user
  my $admin_user = $self->app->dbi->model('user')
    ->select(where => {admin => 1})->one;
  
  return $admin_user;
}

sub default_branch {
  my ($self, $user, $project, $default_branch) = @_;
  
  # Set default branch
  my $dbi = $self->app->dbi;
  if (defined $default_branch) {
    $dbi->model('project')->update(
      {default_branch => $default_branch},
      id => [$user, $project]
    );
  }
  else {
    # Get default branch
    my $default_branch = $dbi->model('project')
      ->select('default_branch', id => [$user, $project])
      ->value;
    
    return $default_branch;
  }
}

sub fork_project {
  my ($self, $user, $original_user, $project) = @_;
  
  # Fork project
  my $dbi = $self->app->dbi;
  my $error;
  eval {
    $dbi->connector->txn(sub {
      
      # Original project id
      my $project_info = $dbi->model('project')->select(
        ['original_pid', 'private'],
        id => [$original_user, $project]
      )->one;
      
      my $original_pid = $project_info->{original_pid};
      
      croak "Can't get original project id"
        unless defined $original_pid && $original_pid > 0;
      
      # Create project
      eval {
        $self->_create_project(
          $user,
          $project,
          {
            original_user => $original_user,
            original_pid => $original_pid,
            private => $project_info->{private}
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

sub is_admin {
  my ($self, $user) = @_;
  
  # Check admin
  my $is_admin = $self->app->dbi->model('user')
    ->select('admin', id => $user)->value;
  
  return $is_admin;
}

sub is_private_project {
  my ($self, $user, $project) = @_;
  
  # Is private
  my $private = $self->app->dbi->model('project')
    ->select('private', id => [$user, $project])->value;
  
  return $private;
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

  return $members;
}

sub create_project {
  my ($self, $user, $project, $opts) = @_;
  
  my $params = {};
  if ($opts->{private}) {
    $params->{private} = 1;
  }
  
  # Create project
  my $dbi = $self->app->dbi;
  my $error;
  eval {
    $dbi->connector->txn(sub {
      eval { $self->_create_project($user, $project, $params) };
      croak $error = $@ if $@;
      eval {$self->_create_rep($user, $project, $opts) };
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
}

sub create_user {
  my ($self, $user, $data) = @_;

  # Create user
  my $dbi = $self->app->dbi;
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
  
  # Delete project
  my $dbi = $self->app->dbi;
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
}

sub delete_user {
  my ($self, $user) = @_;
  
  # Delete user
  my $dbi = $self->app->dbi;
  my $error;
  my $count;
  eval {
    $dbi->connector->txn(sub {
      eval { $count = $self->_delete_db_user($user) };
      croak $error = $@ if $@;
      eval {$self->_delete_user_dir($user) };
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
  
  return $count;
}

sub original_project {
  my ($self, $user, $project) = @_;
  
  # Original project id
  my $dbi = $self->app->dbi;
  my $row = $dbi->model('project')->select(
    ['original_user', 'original_pid'],
    id => [$user, $project]
  )->one;
  
  croak "Original project don't eixsts." unless $row;
  
  # Original project
  my $original_project = $dbi->model('project')->select(
    'name',
    where => {
      user_id => $row->{original_user},
      original_pid => $row->{original_pid}
    }
  )->value;
  
  return unless defined $original_project && length $original_project;
  
  return $original_project;
}

sub original_user {
  my ($self, $user, $project) = @_;
  
  # Orginal user
  my $original_user = $self->app->dbi->model('project')
    ->select('original_user', id => [$user, $project])
    ->value;
  return unless defined $original_user && length $original_user;
  
  return $original_user;
}

sub projects {
  my ($self, $user) = @_;

  # Projects
  my $projects = $self->app->dbi->model('project')->select(
    where => {user_id => $user},
    append => 'order by name'
  )->all;
  
  return $projects;
}

sub users {
  my $self = shift;
  
  # Users
  my $users = $self->app->dbi->model('user')->select(
    where => [':admin{<>}',{admin => 1}],
    append => 'order by id'
  )->all;
  
  return $users;
}

sub rename_project {
  my ($self, $user, $project, $to_project) = @_;
  
  # Rename project
  my $git = $self->app->git;
  my $dbi = $self->app->dbi;
  my $error;
  eval {
    $dbi->connector->txn(sub {
      eval { $self->_rename_project($user, $project, $to_project) };
      croak $error = $@ if $@;
      eval { $self->_rename_rep($user, $project, $to_project) };
      croak $error = $@ if $@;
    });
  };
  croak $error if $error;
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
    "original_pid integer not null default 0",
    "private not null default 0"
  ];
  for my $column (@$project_columns) {
    eval { $dbi->execute("alter table project add column $column") };
  }

  # Check project table
  eval { $dbi->select([qw/default_branch original_user original_pid/], table => 'project') };
  if ($@) {
    my $error = "Can't create project table properly: $@";
    $self->app->log->error($error);
    croak $error;
  }

  # Create collaboration table
  eval {
    my $sql = <<"EOS";
create table collaboration (
  row_id integer primary key autoincrement,
  user_id not null unique default '',
  project_name not null unique default '',
  collaborator_id not null unique default '',
  unique(user_id, project_name, collaborator_id)
);
EOS
    $dbi->execute($sql);
  };
  
  # Check collaboration table
  eval { $dbi->select([qw/row_id user_id project_name collaborator_id/], table => 'collaboration') };
  if ($@) {
    my $error = "Can't create collaboration table properly: $@";
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
  
  # Create project
  my $dbi = $self->app->dbi;
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
  
  # Create repository directory
  my $git = $self->app->git;
  my $rep = $git->rep($user, $project);
  mkdir $rep
    or croak "Can't create directory $rep: $!";

  eval {
    # Git init
    {
      my @git_init_cmd = $git->cmd_rep($rep, 'init', '--bare');
      open my $fh, "-|", @git_init_cmd
        or croak  "Can't open git init --bare:@git_init_cmd";
      close $fh or croak  "Can't execute git init --bare:@git_init_cmd";
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
    open my $update_server_info_fh, "-|", @git_update_server_info_cmd
      or croak "Can't open git --bare update-server-info";
    close $update_server_info_fh or croak "Can't execute git --bare update-server-info";
    move("$rep/hooks/post-update.sample", "$rep/hooks/post-update")
      or croak "Can't move post-update";
    
    # Description
    my $description = $opts->{description};
    $description = '' unless defined $description;
    {
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
      open my $init_fh, "-|", @git_init_cmd
        or croak "Can't open git init";
      close $init_fh or croak "Can't execute git init";
      
      # Add README
      my $file = "$temp_work/README.md";
      open my $readme_fh, '>', $file
        or croak "Can't create $file: $!";
      print $readme_fh "# $project\n";
      print $readme_fh "\n" . encode('UTF-8', $description) . "\n";
      close $readme_fh;
      
      my @git_add_cmd = $git->cmd_rep(
        $temp_work,
        "--work-tree=$temp_work",
        'add',
        'README.md'
      );
      open my $add_fh, "-|", @git_add_cmd
        or croak "Can't open git add";
      close $add_fh or croak "Can't execute git add";
      
      # Commit
      my $author = "$user <$user\@localhost>";
      my @git_commit_cmd = $git->cmd_rep(
        $temp_work,
        "--work-tree=$temp_work",
        'commit',
        '-q',
        "--author=$author",
        '-m',
        'first commit'
      );
      open my $commit_fh, "-|", @git_commit_cmd
        or croak "Can't open git commit";
      close $commit_fh or croak "Can't execute git commit";
      
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
        open my $commit_fh, "-|", "$git_push_cmd 2> /dev/null"
          or croak "Can't open git push";
        close $commit_fh or croak "Can't execute git push";
      }
    }
  };
  if ($@) {
    rmtree $rep;
    croak $@;
  }
}

sub _create_db_user {
  my ($self, $user, $data) = @_;
  
  # Create database user
  $self->app->dbi->model('user')->insert($data, id => $user);
}

sub _create_user_dir {
  my ($self, $user) = @_;
  
  # Create user directory
  my $rep_home = $self->app->git->rep_home;
  my $user_dir = "$rep_home/$user";
  mkpath $user_dir;
}

sub _delete_db_user {
  my ($self, $user) = @_;
  
  # Delete database user
  my $count = $self->app->dbi->model('user')->delete(id => $user);
  
  return $count;
}

sub _delete_user_dir {
  my ($self, $user) = @_;
  
  # Delete user directory
  my $rep_home = $self->app->git->rep_home;
  my $user_dir = "$rep_home/$user";
  rmtree $user_dir;
}

sub _delete_project {
  my ($self, $user, $project) = @_;
  
  # Delete project
  my $dbi = $self->app->dbi;
  $dbi->model('project')->delete(id => [$user, $project]);
}

sub _delete_rep {
  my ($self, $user, $project) = @_;

  # Delete repository
  my $rep_home = $self->app->git->rep_home;
  croak "Can't remove repository. repository home is empty"
    if !defined $rep_home || $rep_home eq '';
  my $rep = "$rep_home/$user/$project.git";
  rmtree $rep;
  croak "Can't remove repository. repository is rest"
    if -e $rep;
}

sub exists_project {
  my ($self, $user, $project) = @_;
  
  # Exists project
  my $dbi = $self->app->dbi;
  my $row = $dbi->model('project')->select(id => [$user, $project])->one;
  
  return $row ? 1 : 0;
}

sub exists_user {
  my ($self, $user) = @_;
  
  # Exists project
  my $row = $self->app->dbi->model('user')->select(id => $user)->one;
  
  return $row ? 1 : 0;
}

sub _exists_rep {
  my ($self, $user, $project) = @_;
  
  # Exists repository
  my $rep = $self->app->git->rep($user, $project);
  
  return -e $rep;
}

sub _fork_rep {
  my ($self, $user, $project, $to_user, $to_project) = @_;
  
  # Fork repository
  my $git = $self->app->git;
  my $rep = $git->rep($user, $project);
  my $to_rep = $git->rep($to_user, $to_project);
  my @cmd = (
    $git->bin,
    'clone',
    '-q',
    '--bare',
    $rep,
    $to_rep
  );
  system(@cmd) == 0
    or croak "Can't fork repository(_fork_rep): @cmd";
  
  # Copy description
  copy "$rep/description", "$to_rep/description"
    or croak "Can't copy description file(_fork_rep)";
}

sub _rename_project {
  my ($self, $user, $project, $renamed_project) = @_;
  
  # Check arguments
  croak "Invalid parameters(_rename_project)"
    unless defined $user && defined $project && defined $renamed_project;
  
  # Rename project
  my $dbi = $self->app->dbi;
  $dbi->model('project')->update(
    {name => $renamed_project},
    id => [$user, $project]
  );
}

sub _rename_rep {
  my ($self, $user, $project, $renamed_project) = @_;
  
  # Check arguments
  croak "Invalid user name or project"
    unless defined $user && defined $project && defined $renamed_project;

  # Rename repository
  my $rep = $self->app->git->rep($user, $project);
  my $renamed_rep = $self->app->git->rep($user, $renamed_project);
  move($rep, $renamed_rep)
    or croak "Can't move $rep to $renamed_rep: $!";
}

1;
