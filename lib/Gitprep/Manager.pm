package Gitprep::Manager;
use Mojo::Base -base;

use Carp 'croak';
use Encode 'encode';
use File::Copy qw/move copy/;
use File::Path qw/mkpath rmtree/;
use File::Temp ();
use Fcntl ':flock';
use Carp 'croak';
use File::Copy qw/copy move/;
use File::Spec;
use Gitprep::Util;

has 'app';
has 'authorized_keys_file';

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

  # Create user columns
  my $user_columns = [
    "admin not null default '0'",
    "password not null default ''",
    "salt not null default ''",
    "mail not null default ''",
    "name not null default ''"
  ];
  for my $column (@$user_columns) {
    eval { $dbi->execute("alter table user add column $column") };
  }
  
  # Check user table
  eval { $dbi->select([qw/row_id id admin password salt mail name/], table => 'user') };
  if ($@) {
    my $error = "Can't create user table properly: $@";
    $self->app->log->error($error);
    croak $error;
  }

  # Create ssh_public_key table
  eval {
    my $sql = <<"EOS";
create table ssh_public_key (
  row_id integer primary key autoincrement,
  key not null unique default ''
);
EOS
    $dbi->execute($sql);
  };

  # Create ssh_public_key columns
  my $ssh_public_key_columns = [
    "user_id not null default ''",
    "title not null default ''"
  ];
  for my $column (@$ssh_public_key_columns) {
    eval { $dbi->execute("alter table ssh_public_key add column $column") };
  }
  
  # Check ssh_public_key table
  eval { $dbi->select([qw/row_id user_id key title/], table => 'ssh_public_key') };
  if ($@) {
    my $error = "Can't create ssh_public_key table properly: $@";
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
    "private not null default 0",
    "ignore_space_change not null default 0",
    "guess_encoding not null default ''"
  ];
  for my $column (@$project_columns) {
    eval { $dbi->execute("alter table project add column $column") };
  }

  # Check project table
  eval {
    $dbi->select(
      [qw/default_branch original_user original_pid private ignore_space_change guess_encoding/],
      table => 'project'
    );
  };
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
  user_id not null default '',
  project_name not null default '',
  collaborator_id not null default '',
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


sub update_authorized_keys_file {
  my $self = shift;

  my $authorized_keys_file = $self->authorized_keys_file;
  if (defined $authorized_keys_file) {
    
    # Lock file
    my $lock_file = $self->app->home->rel_file('lock/authorized_keys');
    open my $lock_fh, $lock_file
      or croak "Can't open lock file $lock_file";
    flock $lock_fh, LOCK_EX
      or croak "Can't lock $lock_file";
    
    # Create authorized_keys_file
    unless (-f $authorized_keys_file) {
      open my $fh, '>', $authorized_keys_file
        or croak "Can't create authorized_keys file: $authorized_keys_file";
      chmod 0600, $authorized_keys_file
        or croak "Can't chmod authorized_keys file: $authorized_keys_file";
    }
    
    # Parse file
    my $result = $self->parse_authorized_keys_file($authorized_keys_file);
    my $before_part = $result->{before_part};
    my $gitprep_part = $result->{gitprep_part};
    my $after_part = $result->{after_part};
    my $start_symbol = $result->{start_symbol};
    my $end_symbol = $result->{end_symbol};
    
    # Backup at first time
    if ($gitprep_part eq '') {
      # Backup original file
      my $to = "$authorized_keys_file.gitprep.original";
      unless (-f $to) {
        copy $authorized_keys_file, $to
          or croak "Can't copy $authorized_keys_file to $to";
      }
    }

    # Create public keys
    my $ssh_public_keys = $self->app->dbi->model('ssh_public_key')->select->all;
    my $ssh_public_keys_str = '';
    for my $key (@$ssh_public_keys) {
      my $ssh_public_key_str = 'command="' . $self->app->home->rel_file('script/gitprep-shell')
        . " $key->{user_id}\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty $key->{key}";
      $ssh_public_keys_str .= "$ssh_public_key_str $key->{user_id}\n\n";
    }
    
    # Output tmp file
    my $output = "$before_part$start_symbol\n\n$ssh_public_keys_str$end_symbol$after_part";
    my $output_file = "$authorized_keys_file.gitprep.tmp";
    open my $out_fh, '>', $output_file
      or croak "Can't create authorized_keys tmp file $output_file";
    print $out_fh $output;
    close $out_fh
      or croak "Can't close authorized_keys tmp file $output_file";

    # Replace
    chmod 0600, $output_file
      or croak "Can't chmod authorized_keys tmp file: $output_file";
    move $output_file, $authorized_keys_file
      or croak "Can't replace $authorized_keys_file by $output_file";
    
    # Unlock file
    flock $lock_fh, LOCK_EX
      or croak "Can't unlock $lock_file"
  }
  else {
    croak qq/authorized_keys file "$authorized_keys_file" is not found./;
  }
}

sub parse_authorized_keys_file {
  my ($self, $file) = @_;
  
  my $start_symbol = "# gitprep start";
  my $end_symbol = "# gitprep end";
  
  # Parse
  open my $fh, '<', $file
    or croak "Can't open authorized_key file $file";
  my $start_symbol_count = 0;
  my $end_symbol_count = 0;
  my $before_part = '';
  my $gitprep_part = '';
  my $after_part = '';
  my $error_prefix = "authorized_keys file $file format error:";
  while (my $line = <$fh>) {
    if ($line =~ /^$start_symbol/) {
      if ($start_symbol_count > 0) {
        croak qq/$error_prefix "$start_symbol" is found more than one/;
      }
      else {
        if ($end_symbol_count > 0) {
          croak qq/$error_prefix "$end_symbol" is found before "$start_symbol"/;
        }
        else {
          $start_symbol_count++;
        }
      }
    }
    elsif ($line =~ /^$end_symbol/) {
      if ($end_symbol_count > 0) {
        croak qq/$error_prefix "$end_symbol" is found more than one/;
      }
      else {
        $end_symbol_count++;
      }
    }
    elsif ($start_symbol_count == 0 && $end_symbol_count == 0) {
      $before_part .= $line;
    }
    elsif ($start_symbol_count == 1 && $end_symbol_count == 0) {
      $gitprep_part .= $line;
    }
    elsif ($start_symbol_count == 1 && $end_symbol_count == 1) {
      $after_part .= $line;
    }
  }
  
  my $result = {
    start_symbol => $start_symbol,
    end_symbol => $end_symbol,
    before_part => $before_part,
    gitprep_part => $gitprep_part,
    after_part => $after_part
  };
  
  return $result;
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
      Gitprep::Util::run_command(@git_init_cmd)
        or croak  "Can't execute git init --bare:@git_init_cmd";
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
    Gitprep::Util::run_command(@git_update_server_info_cmd)
      or croak "Can't execute git --bare update-server-info";
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
      my $home_tmp_dir = $self->app->home->rel_file('tmp');
      
      my $temp_dir =  File::Temp->newdir(DIR => $home_tmp_dir);
      my $temp_work = "$temp_dir/work";
      mkdir $temp_work
        or croak "Can't create directory $temp_work: $!";
      
      # Git init
      my @git_init_cmd = $git->cmd_rep($temp_work, 'init', '-q');
      Gitprep::Util::run_command(@git_init_cmd)
        or croak "Can't execute git init: @git_init_cmd";
      
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
      Gitprep::Util::run_command(@git_add_cmd)
        or croak "Can't execute git add: @git_add_cmd";
      
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
      Gitprep::Util::run_command(@git_commit_cmd)
        or croak "Can't execute git commit: @git_commit_cmd";
      
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
        Gitprep::Util::run_command(@git_push_cmd)
          or croak "Can't execute git push: @git_push_cmd";
      }
    }
  };
  if (my $e = $@) {
    rmtree $rep;
    croak $e;
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
  Gitprep::Util::run_command(@cmd)
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
