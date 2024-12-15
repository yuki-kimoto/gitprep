package Gitprep::Manager;
use Mojo::Base -base;

use Carp 'croak';
use Encode 'encode';
use File::Copy qw/move copy/;
use File::Path qw/mkpath rmtree/;
use File::Temp ();
use Fcntl ':flock';
use Carp 'croak';
use File::Spec;
use Gitprep::Util;

has 'app';
has 'authorized_keys_file';

has '_tmp_branch' => '__gitprep_tmp_branch__';

sub get_remotes {
  my ($self, $rep_info) = @_;

  my @git_remote_show_cmd = $self->app->git->cmd($rep_info, 'remote', '-v', 'show');
  open my $fh, '-|', @git_remote_show_cmd
    or croak "Execute git remote cmd:@git_remote_show_cmd";
  my %remotes;
  while (my $line = <$fh>) {
    my ($remote, $url) = split /\s+/, $line;
    $remotes{$remote} = $url;
  }
  return \%remotes;
}

sub prepare_merge {
  my ($self, $work_rep_info, $base_rep_info, $base_branch, $target_rep_info, $target_branch) = @_;

  my $git = $self->app->git;

  # Fetch base repository
  my $base_user_id = $base_rep_info->{user};
  my @git_fetch_base_cmd = $git->cmd($work_rep_info, 'fetch', 'origin');
  Gitprep::Util::run_command(@git_fetch_base_cmd)
    or Carp::croak "Can't execute git fetch: @git_fetch_base_cmd";

  # Configure remote for target repository
  my $target_remote = $target_rep_info->{user} . '/' . $target_rep_info->{project};
  my $remotes = $self->get_remotes($work_rep_info);
  if (exists $remotes->{$target_remote} && $remotes->{$target_remote} ne $target_rep_info->{root}) {
    my @git_remote_remove_cmd = $git->cmd($work_rep_info, 'remote', 'remove', $target_remote);
    Gitprep::Util::run_command(@git_remote_remove_cmd)
      or Carp::croak "Can't execute git remote @git_remote_remove_cmd";
    delete $remotes->{$target_remote};
  }
  if (!exists $remotes->{$target_remote}) {
    my @git_remote_add_cmd = $git->cmd($work_rep_info, 'remote', 'add', $target_remote, $target_rep_info->{root});
    Gitprep::Util::run_command(@git_remote_add_cmd)
      or Carp::croak "Can't execute git remote @git_remote_add_cmd";
  }

  # Fetch target repository
  my @git_fetch_target_cmd = $git->cmd($work_rep_info, 'fetch', $target_remote);

  Gitprep::Util::run_command(@git_fetch_target_cmd)
    or Carp::croak "Can't execute git fetch: @git_fetch_target_cmd";

  # Ensure no diff
  my @git_reset_hard_cmd = $git->cmd(
    $work_rep_info,
    'reset',
    '--hard'
  );
  Gitprep::Util::run_command(@git_reset_hard_cmd)
    or Carp::croak "Can't execute git reset --hard: @git_reset_hard_cmd";

  # Checkout first branch
  my $tmp_branch = $self->_tmp_branch;
  my $branch_names = $self->app->git->branch_names($work_rep_info);
  my $first_branch;
  for my $branch_name (@$branch_names) {
    if ($branch_name ne $tmp_branch) {
      $first_branch = $branch_name;
      last;
    }
  }
  my @git_checkout_first_branch = $self->app->git->cmd(
    $work_rep_info,
    'checkout',
    $first_branch
  );
  Gitprep::Util::run_command(@git_checkout_first_branch)
    or Carp::croak "Can't execute git checkout: @git_checkout_first_branch";
  
  # Delete temporary branch if it exists
  if (grep { $_ eq $tmp_branch } @$branch_names) {
    my @git_branch_remove_cmd = $git->cmd(
      $work_rep_info,
      'branch',
      '-D',
      $tmp_branch
    );
    Gitprep::Util::run_command(@git_branch_remove_cmd)
      or Carp::croak "Can't execute git branch: @git_branch_remove_cmd";
  }

  # Create temporary branch from base branch and check it out
  my @git_branch_cmd = $git->cmd(
    $work_rep_info,
    'checkout',
    '-b',
    $tmp_branch,
    "origin/$base_branch"
  );
  Gitprep::Util::run_command(@git_branch_cmd)
    or Carp::croak "Can't execute git checkout @git_branch_cmd";
}

sub merge {
  my ($self, $work_rep_info, $target_rep_info, $target_branch, $pull_request_number) = @_;

  my $target_remote = $target_rep_info->{user} . '/' . $target_rep_info->{project};
  my $object_id = $self->app->git->ref_to_object_id($work_rep_info, "$target_remote/$target_branch");
  
  my $message;
  my $target_user_id = $target_rep_info->{user};
  if (defined $pull_request_number) {
    $message = "Merge pull request #$pull_request_number from $target_user_id/$target_branch";
  }
  else {
    $message = "Merge from $target_user_id/$target_branch";
  }
  
  # Merge
  my @git_merge_cmd = $self->app->git->cmd(
    $work_rep_info,
    'merge',
    '--no-ff',
    "--message=$message",
    $object_id
  );
  # 
  
  my $success = Gitprep::Util::run_command(@git_merge_cmd);
  
  return $success;
}

sub get_patch {
  my ($self, $work_rep_info, $target_rep_info, $target_branch) = @_;

  my $target_remote = $target_rep_info->{user} . '/' . $target_rep_info->{project};
  my $object_id = $self->app->git->ref_to_object_id($work_rep_info, "$target_remote/$target_branch");
  
  # Format patch
  my @git_format_patch_cmd = $self->app->git->cmd(
    $work_rep_info,
    'format-patch',
    '--stdout',
    "HEAD..$object_id"
  );
  
  open my $fh, '-|', @git_format_patch_cmd
    or croak "Execute git format-patch cmd:@git_format_patch_cmd";
  
  my $patch = do { local $/; <$fh> };
  
  return $patch;
}

sub merge_base {
  my ($self, $work_rep_info, $base_branch, $target_rep_info, $target_branch) = @_;

  my $target_remote = $target_rep_info->{user} . '/' . $target_rep_info->{project};
  my @git_merge_base_cmd = $self->app->git->cmd(
    $work_rep_info,
    'merge-base',
    "$target_remote/$target_branch",
    "origin/$base_branch"
  );
  open my $fh, '-|', @git_merge_base_cmd or return;
  my $merge_base = <$fh>;
  chomp $merge_base;
  return $merge_base;
}

sub push {
  my ($self, $work_rep_info, $base_branch) = @_;
  
  # Push
  my $tmp_branch = $self->_tmp_branch;
  my @git_push_cmd = $self->app->git->cmd(
    $work_rep_info,
    'push',
    'origin',
    "$tmp_branch:$base_branch"
  );
  Gitprep::Util::run_command(@git_push_cmd)
    or Carp::croak "Can't execute git push: @git_push_cmd";
}

sub lock_rep {
  my ($self, $rep_info) = @_;
  
  my $git_dir = $rep_info->{git_dir};
  my $lock_file = "$git_dir/config";
  
  open my $lock_fh, '<', $lock_file
    or croak "Can't open lock file $lock_file: $!";
    
  flock $lock_fh, LOCK_EX
    or croak "Can't lock $lock_file";
  
  return $lock_fh;
}

sub create_work_rep {
  my ($self, $user, $project) = @_;
  
  # Remote repository
  my $rep_info = $self->app->rep_info($user, $project);
  my $rep_git_dir = $rep_info->{git_dir};
  
  # Working repository
  my $work_rep_info = $self->app->work_rep_info($user, $project);
  my $work_tree = $work_rep_info->{work_tree};
  
  # Create working repository if it doesn't exist
  unless (-e $work_tree) {

    # git clone
    my @git_clone_cmd = ($self->app->git->bin, 'clone', $rep_git_dir, $work_tree);
    Gitprep::Util::run_command(@git_clone_cmd)
      or croak "Can't git clone: @git_clone_cmd";
    
    # Set user name
    my @git_config_user_name = $self->app->git->cmd(
      $work_rep_info,
      'config',
      'user.name',
      $user
    );
    Gitprep::Util::run_command(@git_config_user_name)
      or croak "Can't execute git config: @git_config_user_name";
    
    # Set user email
    my $user_email = $self->app->dbi->model('user')->select('email', where => {id => $user})->value;
    my @git_config_user_email = $self->app->git->cmd(
      $work_rep_info,
      'config',
      'user.email',
      "$user_email"
    );
    Gitprep::Util::run_command(@git_config_user_email)
      or croak "Can't execute git config: @git_config_user_email";
  }
}

sub admin_user {
  my $self = shift;
  
  # Admin user
  my $admin_user = $self->app->dbi->model('user')
    ->select(where => {admin => 1})->one;
  
  return $admin_user;
}

sub fork_project {
  my ($self, $forked_user_id, $user_id, $project_id) = @_;
  
  my $user_row_id = $self->api->get_user_row_id($user_id);
  
  # Fork project
  my $dbi = $self->app->dbi;
  my $error;
  eval {
    $dbi->connector->txn(sub {
      
      # Original project id
      my $project = $dbi->model('project')->select(
        {__MY__ => ['row_id', 'private']},
        where => {'user.id' => $user_id, 'project.id' => $project_id}
      )->one;
      
      # Create project
      eval {
        $self->_create_project(
          $forked_user_id,
          $project_id,
          {
            original_project => $project->{row_id},
            private => $project->{private}
          }
        );
      };
      croak $error = $@ if $@;
      
      # Create repository
      eval {
        $self->_fork_rep($user_id, $project_id, $forked_user_id, $project_id);
      };
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
}

sub is_admin {
  my ($self, $user_id) = @_;
  
  # Check admin
  my $is_admin = $self->app->dbi->model('user')
    ->select('admin', where => {id => $user_id})->value;
  
  return $is_admin;
}

sub is_private_project {
  my ($self, $user_id, $project_id) = @_;
  
  my $user_row_id = $self->api->get_user_row_id($user_id);
  
  # Is private
  my $private = $self->app->dbi->model('project')->select(
    'private', where => {user => $user_row_id, id => $project_id}
  )->value;
  
  return $private;
}

sub api { shift->app->gitprep_api }


sub member_projects {
  my ($self, $user_id, $project_id, $scope) = @_;

  # Scope values:
  # one: direct children (default).
  # base: current project.
  # sub: current project and descendant forks.
  # subordinates: descendant forks.
  # all: the complete frok tree from its root.
  $scope = lc($scope // 'one');
  
  # DBI
  my $dbi = $self->app->dbi;
  my @results;

  # Recursive gathering of descendant forks
  local *closure = sub {
    my ($project, $levels) = @_;
    $levels //= 9999999999;
    if (--$levels > 0) {
      my $children = $dbi->model('project')->select(
        [
          {__MY__ => ['row_id', 'id']},
          {user => ['id']}
        ],
        where => {'project.original_project' => $project->{row_id}}
      )->all;
      closure($_, $levels) for (@$children);
    }
    CORE::push @results, $project;
  };

  # Get current project
  my $project = $dbi->model('project')->select(
    [
      {__MY__ => ['row_id', 'id', 'original_project']},
      {user => ['id']}
    ],
    where => {'user.id' => $user_id, 'project.id' => $project_id}
  )->one;

  return \@results unless $project
;
  if ($scope eq 'base') {
    closure($project, 1);
  } elsif ($scope eq 'sub') {
    closure($project);
  } elsif ($scope eq 'all') {
    # Get root of all member projects
    while ($project && $project->{original_project}) {
      $project = $dbi->model('project')->select(
        [
          {__MY__ => ['row_id', 'id', 'original_project']},
          {user => ['id']}
        ],
        where => {'project.row_id' => $project->{original_project}}
      )->one;
    }
    closure($project);
  }
  else {
    closure($project, $scope eq 'one'? 2: undef);
    pop @results;       # Remove current project.
  }

  @results = sort {"$a->{'user.id'} $a->{id}" cmp "$b->{'user.id'} $b->{id}"} @results;
  return \@results;
}

sub create_project {
  my ($self, $user_id, $project_id, $opts) = @_;
  
  my $params = {};
  $opts //= {};
  if ($opts->{private}) {
    $params->{private} = 1;
  }
  
  # Create project
  my $dbi = $self->app->dbi;
  my $error;

  eval {
    $dbi->connector->txn(sub {
      eval { $self->_create_project($user_id, $project_id, $params) };
      croak $error = $@ if $@;
      eval {$self->_create_rep($user_id, $project_id, $opts) };
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
      eval {$self->update_authorized_keys_file() };
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
  
  return $count;
}

sub original_project {
  my ($self, $user_id, $project_id) = @_;
  
  my $user_row_id = $self->api->get_user_row_id($user_id);
  
  # Original project id
  my $dbi = $self->app->dbi;
  my $original_project_row_id = $dbi->model('project')->select(
    'original_project',
    where => {user => $user_row_id, id => $project_id}
  )->value;
  
  croak "Original project doesn't exist." unless defined $original_project_row_id;
  
  # Original project
  my $original_project = $dbi->model('project')->select(
    [
      {__MY__ => '*'},
      {user => ['id']}
    ],
    where => {
      'project.row_id' => $original_project_row_id
    }
  )->one;
  
  return unless defined $original_project;
  
  return $original_project;
}

sub child_project {
  my ($self, $user_id, $project_id, $child_user_id) = @_;
  
  my $project_row_id = $self->app->dbi->model('project')->select(
    'project.row_id', where => {'user.id' => $user_id, 'project.id' => $project_id}
  )->value;
  
  my $child_project = $self->app->dbi->model('project')->select(
    [
      {__MY__ => '*'},
      {user => ['id']}
    ],
    where => {
      'project.original_project' => $project_row_id,
      'user.id' => $child_user_id
    }
  )->one;
  
  return $child_project;
}

sub projects {
  my ($self, $user_id) = @_;
  
  my $user_row_id = $self->app->dbi->model('user')->select('row_id', where => {id => $user_id})->value;
  
  # Projects
  my $projects = $self->app->dbi->model('project')->select(
    where => {user => $user_row_id},
    append => 'order by id'
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
  my $app = $self->app;
  my $git = $app->git;
  my $dbi = $app->dbi;
  my $has_wiki = $dbi->model('wiki')->select('count(*)', where => {
    'project.id' => $project
  })->value;
  my $error;
  eval {
    $dbi->connector->txn(sub {
      eval { $self->_rename_project($user, $project, $to_project) };
      croak $error = $@ if $@;

      eval { $self->_rename_rep($user, $project, $to_project, sub () {
        return $app->rep_info(@_);}
      ) };
      croak $error = $@ if $@;
      eval { $self->_rename_rep($user, $project, $to_project, sub () {
        return $app->work_rep_info(@_);}
      ) };
      croak $error = $@ if $@;
      if ($has_wiki) {
        eval { $self->_rename_rep($user, $project, $to_project, sub () {
          return $app->wiki_rep_info(@_);}
        ) };
        croak $error = $@ if $@;
        eval { $self->_rename_rep($user, $project, $to_project, sub () {
          return $app->wiki_work_rep_info(@_);}
        ) };
        croak $error = $@ if $@;
      }
    });
  };
  croak $error if $error;
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
    my $ssh_public_keys = $self->app->dbi->model('ssh_public_key')->select(
      [
        {__MY__ => '*'},
        {user => ['id']}
      ]
    )->all;
    my $ssh_public_keys_str = '';
    for my $key (@$ssh_public_keys) {
      my $ssh_public_key_str = 'command="' . $self->app->home->rel_file('script/gitprep-shell')
        . " $key->{'user.id'}\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty $key->{key}";
      $ssh_public_keys_str .= "$ssh_public_key_str $key->{'user.id'}\n\n";
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
  my ($self, $user_id, $project_id, $params) = @_;
  
  my $user_row_id = $self->api->get_user_row_id($user_id);
  $params ||= {};
  $params->{user} = $user_row_id;
  $params->{id} = $project_id;
  
  # Create project
  my $dbi = $self->app->dbi;
  $dbi->connector->txn(sub {
    $dbi->model('project')->insert($params);
    # Auto-watch for owner.
    my $project_row_id = $dbi->model('project')->select('row_id',
      where => {user => $user_row_id, id => $project_id}
    )->value;
    $dbi->model('watch')->insert({
      user => $user_row_id,
      project => $project_row_id
    });
  });
}

sub _create_rep {
  my ($self, $user, $project, $opts) = @_;

  chomp(my $default_branch = $opts->{default_branch} // 'master');
 
  # Create repository directory
  my $git = $self->app->git;

  my $rep_info = $self->app->rep_info($user, $project);
  my $rep_git_dir = $rep_info->{git_dir};
  
  mkdir $rep_git_dir
    or croak "Can't create directory $rep_git_dir: $!";
  
  eval {
    # Git init
    {
      my @git_init_args = ($rep_info, 'init', '--bare');
      if ($default_branch ne 'master' ) {
      	CORE::push( @git_init_args, ('--initial-branch=' . $default_branch));
      }
      my @git_init_cmd = $git->cmd(@git_init_args);

      Gitprep::Util::run_command(@git_init_cmd)
        or croak  "Can't execute git init --bare:@git_init_cmd";
    }
    
    # Add git-daemon-export-ok
    {
      my $file = "$rep_git_dir/git-daemon-export-ok";
      open my $fh, '>', $file
        or croak "Can't create git-daemon-export-ok: $!"
    }
    
    # HTTP support
    my @git_update_server_info_cmd = $git->cmd(
      $rep_info,
      '--bare',
      'update-server-info'
    );
    Gitprep::Util::run_command(@git_update_server_info_cmd)
      or croak "Can't execute git --bare update-server-info";
    move("$rep_git_dir/hooks/post-update.sample", "$rep_git_dir/hooks/post-update")
      or croak "Can't move post-update";
    
    # Description
    my $description = $opts->{description};
    $description = '' unless defined $description;
    {
      my $file = "$rep_git_dir/description";
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
      
      # Temp directory
      my $temp_dir =  File::Temp->newdir(DIR => $home_tmp_dir);
      
      # Working repository
      my $work_rep_work_tree = "$temp_dir/work";
      my $work_rep_git_dir = "$work_rep_work_tree/.git";
      my $work_rep_info = {
        work_tree => $work_rep_work_tree,
        git_dir => $work_rep_git_dir
      };
      
      mkdir $work_rep_work_tree
        or croak "Can't create directory $work_rep_work_tree: $!";
      
      # Git init
      my @work_repo_cmd = ($work_rep_info, 'init', '-q');
      if ($default_branch ne 'master') {
        CORE::push( @work_repo_cmd, '--initial-branch=' . $default_branch );
      }
      my @git_init_cmd = $git->cmd(@work_repo_cmd);
      Gitprep::Util::run_command(@git_init_cmd)
        or croak "Can't execute git init: @git_init_cmd";
      
      # Add README
      my $file = "$work_rep_work_tree/README.md";
      open my $readme_fh, '>', $file
        or croak "Can't create $file: $!";
      print $readme_fh "# $project\n";
      print $readme_fh "\n" . encode('UTF-8', $description) . "\n";
      close $readme_fh;
      
      my @git_add_cmd = $git->cmd(
        $work_rep_info,
        'add',
        'README.md'
      );
      
      Gitprep::Util::run_command(@git_add_cmd)
        or croak "Can't execute git add: @git_add_cmd";
      
      # Set user name
      my @git_config_user_name = $git->cmd(
        $work_rep_info,
        'config',
        'user.name',
        $user
      );
      Gitprep::Util::run_command(@git_config_user_name)
        or croak "Can't execute git config: @git_config_user_name";
      
      # Set user email
      my $user_email = $self->app->dbi->model('user')->select('email', where => {id => $user})->value;
      my @git_config_user_email = $git->cmd(
        $work_rep_info,
        'config',
        'user.email',
        "$user_email"
      );
      Gitprep::Util::run_command(@git_config_user_email)
        or croak "Can't execute git config: @git_config_user_email";
      
      # Commit
      my @git_commit_cmd = $git->cmd(
        $work_rep_info,
        'commit',
        '-q',
        '-m',
        'first commit'
      );

      Gitprep::Util::run_command(@git_commit_cmd)
        or croak "Can't execute git commit: @git_commit_cmd";
      
      # Push
      {
        my @git_push_cmd = $git->cmd(
          $work_rep_info,
          'push',
          '-q',
          $rep_git_dir,
          $default_branch
        );
        # (This is bad, but --quiet option can't supress in old git)
        Gitprep::Util::run_command(@git_push_cmd)
          or croak "Can't execute git push: @git_push_cmd";
      }
    }
  };
  if (my $e = $@) {
    rmtree $rep_git_dir;
    croak $e;
  }
}

sub create_wiki_rep {
  my ($self, $user, $project) = @_;
  
  # Create repository directory
  my $git = $self->app->git;
  
  my $wiki_rep_info = $self->app->wiki_rep_info($user, $project);
  my $wiki_rep_git_dir = $wiki_rep_info->{git_dir};
  
  mkdir $wiki_rep_git_dir
    or croak "Can't create directory $wiki_rep_git_dir: $!";
  
  eval {
    # Git init
    {
      my @git_init_cmd = $git->cmd($wiki_rep_info, 'init', '--bare');
      Gitprep::Util::run_command(@git_init_cmd)
        or croak  "Can't execute git init --bare:@git_init_cmd";
    }
    
    # Add git-daemon-export-ok
    {
      my $file = "$wiki_rep_git_dir/git-daemon-export-ok";
      open my $fh, '>', $file
        or croak "Can't create git-daemon-export-ok: $!"
    }
    
    # HTTP support
    my @git_update_server_info_cmd = $git->cmd(
      $wiki_rep_info,
      '--bare',
      'update-server-info'
    );
    Gitprep::Util::run_command(@git_update_server_info_cmd)
      or croak "Can't execute git --bare update-server-info";
    move("$wiki_rep_git_dir/hooks/post-update.sample", "$wiki_rep_git_dir/hooks/post-update")
      or croak "Can't move post-update";
  };
  if (my $e = $@) {
    rmtree $wiki_rep_git_dir;
    croak $e;
  }
}

sub create_wiki_work_rep {
  my ($self, $user, $project) = @_;
  
  # Remote repository
  my $wiki_rep_info = $self->app->wiki_rep_info($user, $project);
  my $wiki_rep_git_dir = $wiki_rep_info->{git_dir};
  
  # Working repository
  my $wiki_work_rep_info = $self->app->wiki_work_rep_info($user, $project);
  my $work_tree = $wiki_work_rep_info->{work_tree};
  
  # Create working repository if it don't exist
  unless (-e $work_tree) {

    # git clone
    my @git_clone_cmd = ($self->app->git->bin, 'clone', $wiki_rep_git_dir, $work_tree);
    Gitprep::Util::run_command(@git_clone_cmd)
      or croak "Can't git clone: @git_clone_cmd";
    
    # Set user name
    my @git_config_user_name = $self->app->git->cmd(
      $wiki_work_rep_info,
      'config',
      'user.name',
      $user
    );
    Gitprep::Util::run_command(@git_config_user_name)
      or croak "Can't execute git config: @git_config_user_name";
    
    # Set user email
    my $user_email = $self->app->dbi->model('user')->select('email', where => {id => $user})->value;
    my @git_config_user_email = $self->app->git->cmd(
      $wiki_work_rep_info,
      'config',
      'user.email',
      "$user_email"
    );
    Gitprep::Util::run_command(@git_config_user_email)
      or croak "Can't execute git config: @git_config_user_email";
  }
}

sub _create_db_user {
  my ($self, $user_id, $data) = @_;
  
  $data->{id} = $user_id;
  
  # Create database user
  $self->app->dbi->model('user')->insert($data);
}

sub _create_user_dir {
  my ($self, $user) = @_;
  
  # Create user directory
  my $rep_home = $self->app->rep_home;
  my $user_dir = "$rep_home/$user";
  mkpath $user_dir;
}

sub _delete_db_user {
  my ($self, $user_id) = @_;

  # Delete database user
  my $dbi = $self->app->dbi;
  my $row_id = $dbi->model('user')->select(
    'row_id',
     where => {
       id => $user_id
     }
  )->value;
  return 0E0 unless $row_id;
  my $projects = $dbi->model('project')->select(
     {__MY__ => ['id']},
    where => {
      'project.user' => $row_id
    }
  )->all;
  foreach my $project (@$projects) {
    $self->_delete_project($user_id, $project->{id});
  }
  $dbi->model('collaboration')->delete(where => {user => $row_id});
  $dbi->model('subscription')->delete(where => {user => $row_id});
  $dbi->model('watch')->delete(where => {user => $row_id});
  $dbi->model('ssh_public_key')->delete(where => {user => $row_id});
  my $count = $dbi->model('user')->delete(where => {id => $user_id});

  return $count;
}

sub _delete_user_dir {
  my ($self, $user) = @_;
  
  # Delete user directory
  my $rep_home = $self->app->rep_home;
  my $user_dir = "$rep_home/$user";
  rmtree $user_dir;
}

sub _delete_ruleset {
  my ($self, $ruleset) = @_;

  # Delete a ruleset.

  my $dbi = $self->app->dbi;
  $dbi->model('ruleset_selector')->delete(where => {
    ruleset => $ruleset->{row_id}
  });
  $dbi->model('ruleset')->delete(where => {row_id => $ruleset->{row_id}});
}

sub delete_ruleset {
  my ($self, $ruleset) = @_;

  # Delete ruleset.
  my $dbi = $self->app->dbi;
  my $error;
  eval {
    $dbi->connector->txn(sub {
      eval { $self->_delete_ruleset($ruleset) };
      croak $error = $@ if $@;
    });
  };
  croak $error if $@;
}

sub _delete_issue {
  my ($self, $issue) = @_;

  # Delete issue/pull request

  my $dbi = $self->app->dbi;
  $dbi->model('subscription')->delete(where => {issue => $issue->{row_id}});
  if ($issue->{pull_request}) {
    $dbi->model('pull_request')->delete(where => {
      row_id => $issue->{pull_request}
    });
  }
  $dbi->model('issue_message')->delete(where => {issue => $issue->{row_id}});
  $dbi->model('issue')->delete(where => {row_id => $issue->{row_id}});
}

sub _change_upstream_project {
  my ($self, $project) = @_;

  # The current project is not an upstream anymore: chose another one.
  my $dbi = $self->app->dbi;
  my $new_upstream = $project->{original_project};

  if (!$new_upstream) {
    # Use a fork as the new upstream project
    my $forks = $dbi->model('project')->select(['row_id', 'id'],
      where => {
        original_project => $project->{row_id}
      }
    )->all;
    # Prefer a fork with the same visibility, same project name,
    # maximizing fork and watch counts
    my $best;
    for my $fork (@$forks) {
      $fork->{same_id} = $fork->{id} eq $project->{id};
      $fork->{fork_count} = $dbi->model('project')->select('count(*)',
        where => {
          original_project => $fork->{row_id}
        }
      )->value;
      $fork->{watch_count} = $dbi->model('watch')->select('count(*)',
        where => {
          project => $fork->{row_id}
        }
      )->value;
      if (!$best) {
        $best = $fork;
      } elsif ($fork->{public} != $best->{public}) {
        $best = $fork unless $fork->{public} > $best->{public} ||
          $fork->{public} == $project->{public};
      } elsif ($fork->{same_id} != $best->{same_id}) {
        $best = $fork unless $fork->{same_id} < $best->{same_id};
      } elsif ($fork->{fork_count} != $best->{fork_count}) {
        $best = $fork unless $fork->{fork_count} < $best->{fork_count};
      } elsif ($fork->{watch_count} > $best->{watch_count}) {
        $best = $fork;
      }
    }
    return unless $best;
    $new_upstream = $best->{row_id};
  }
  $dbi->model('project')->update({original_project => $new_upstream},
    where => {original_project => $project->{row_id}}
  );
  if ($new_upstream != $project->{original_project}) {
    $dbi->model('project')->update(
      {original_project => $project->{original_project}},
      where => {row_id => $new_upstream}
    );
    $dbi->model('project')->update(
      {original_project => $new_upstream},
      where => {row_id => $project->{row_id}}
    );
  }
}

sub _delete_project {
  my ($self, $user_id, $project_id) = @_;

  # Delete project

  my $dbi = $self->app->dbi;
  my $project = $dbi->model('project')->select(
    {__MY__ => '*'},
    where => {
      'project.id' => $project_id,
      'user.id' => $user_id
    }
  )->one;
  my $row_id = $project->{row_id};

  # First, assign a new upstream to forks.
  $self->_change_upstream_project($project);

  # Delete project issues and pull requests.
  # Also delete other projects' pull requests that target the current project.
  my $issues = $dbi->model('issue')->select(
    {__MY__ => '*'},
    where => [
      ['or', ':project{=}', ':pull_request.target_project{=}'],
      {
        project => $row_id,
        'pull_request.target_project' => $row_id
      }
    ]
  )->all;
  for my $issue (@$issues) {
    $self->_delete_issue($issue);
  }

  # Delete rulesets.
  my $rulesets = $dbi->model('ruleset')->select(
    where => {project => $row_id}
  )->all;
  for my $ruleset (@$rulesets) {
    $self->_delete_ruleset($ruleset);
  }

  # Delete project's wiki.
  if ($dbi->model('wiki')->delete(
    where => {project => $row_id}
  ) > 0) {
    $self->_delete_wiki_rep($user_id, $project_id);
  }

  $dbi->model('collaboration')->delete(where => {project => $row_id});
  $dbi->model('watch')->delete(where => {project => $row_id});
  $dbi->model('label')->delete(where => {project => $row_id});
  $dbi->model('project')->delete(where => {row_id => $row_id});
}

sub _delete_rep {
  my ($self, $user, $project) = @_;

  # Delete repository
  my $rep_home = $self->app->rep_home;
  croak "Can't remove repository. repository home is empty"
    if !defined $rep_home || $rep_home eq '';
  my $app = $self->app;
  for my $ri ($app->rep_info($user, $project), $app->work_rep_info($user, $project)) {
    my $rep = $ri->{root};
    if (-e $rep) {
      rmtree $rep;
      croak "Can't remove repository. repository is rest"
        if -e $rep;
    }
  }
}

sub _delete_wiki_rep {
  my ($self, $user, $project) = @_;

  # Delete wiki repository
  my $app = $self->app;
  for my $ri ($app->wiki_rep_info($user, $project), $app->wiki_work_rep_info($user, $project)) {
    my $rep =  $ri->{root};
    if (-e $rep) {
      rmtree $rep;
      croak "Can't remove wiki repository"
        if -e $rep;
    }
  }
}

sub exists_project {
  my ($self, $user_id, $project_id) = @_;
  
  my $user_row_id = $self->api->get_user_row_id($user_id);
  
  # Exists project
  my $dbi = $self->app->dbi;
  my $row = $dbi->model('project')->select(where => {user => $user_row_id, id => $project_id})->one;
  
  return $row ? 1 : 0;
}

sub exists_user {
  my ($self, $user_id) = @_;
  
  # Return true if user exists.
  my $row = $self->app->dbi->model('user')->select(where => {id => $user_id})->one;
  
  return $row ? 1 : 0;
}

sub _exists_rep {
  my ($self, $user, $project) = @_;
  
  # Exists repository
  my $rep_info = $self->app->rep_info($user, $project);
  my $rep_git_dir = $rep_info->{git_dir};
  
  return -e $rep_git_dir;
}

sub _fork_rep {
  my ($self, $user_id, $project_id, $to_user_id, $to_project_id) = @_;
  
  # Fork repository
  my $git = $self->app->git;
  
  my $rep_info = $self->app->rep_info($user_id, $project_id);
  my $rep_git_dir = $rep_info->{git_dir};
  
  my $to_rep_info = $self->app->rep_info($to_user_id, $to_project_id);
  my $to_rep_git_dir = $to_rep_info->{git_dir};

  my @cmd = (
    $git->bin,
    'clone',
    '-q',
    '--bare',
    $rep_git_dir,
    $to_rep_git_dir
  );
  Gitprep::Util::run_command(@cmd)
    or croak "Can't fork repository(_fork_rep): @cmd";
  
  # Copy description
  copy "$rep_git_dir/description", "$to_rep_git_dir/description"
    or croak "Can't copy description file(_fork_rep)";
}

sub _rename_project {
  my ($self, $user_id, $project_id, $renamed_project_id) = @_;
  
  my $user_row_id = $self->api->get_user_row_id($user_id);
  
  # Check arguments
  croak "Invalid parameters(_rename_project)"
    unless defined $user_id && defined $project_id && defined $renamed_project_id;
  
  # Rename project
  my $dbi = $self->app->dbi;
  $dbi->model('project')->update(
    {id => $renamed_project_id},
    where => {user => $user_row_id, id => $project_id}
  );
}

sub _rename_rep {
  my ($self, $user, $project, $renamed_project, $info_func) = @_;

  # Check arguments
  croak "Invalid user name or project"
    unless defined $user && defined $project && defined $renamed_project;

  # Rename repository
  my $rep_info = $info_func->($user, $project);
  my $rep_git_dir = $rep_info->{root};

  my $renamed_rep_info = $info_func->($user, $renamed_project);
  my $renamed_rep_git_dir = $renamed_rep_info->{root};

  if (-e $rep_git_dir) {
    my $lock_fh = $self->lock_rep($rep_info);
    move($rep_git_dir, $renamed_rep_git_dir)
      or croak "Can't move $rep_git_dir to $renamed_rep_git_dir: $!";
  }
}

sub rules {
  my $self = shift;
  my $git = $self->app->git;

  return [
    {id => 'creation', label => 'Restrict creations', default => 0, explain =>
      'Only allow users with bypass permission to create matching refs',
      error => ' creation',
      check => sub () {
        my ($rep_info, $old, $new, $ref) = @_;
        return !$old;
      }
    },
    {id => 'updating', label => 'Restrict updates', default => 0, explain =>
      'Only allow users with bypass permission to update matching refs',
      error => ' update',
      check => sub () {
        my ($rep_info, $old, $new, $ref) = @_;
        return $old && $new;
      }
    },
    {id => 'deletion', label => 'Restrict deletions', default => 1, explain =>
      'Only allow users with bypass permissions to delete matching refs',
      error => ' deletion',
      check => sub () {
        my ($rep_info, $old, $new, $ref) = @_;
        return !$new;
      }
    },
    {id => 'required_signatures', label => 'Require signed commits',
      default => 0, explain =>
      'Commits pushed to matching refs must have verified signatures',
      error => ': unsigned commits',
      check => sub () {
        my ($rep_info, $old, $new, $ref) = @_;
        return 0 unless $new;
        my $revs = $git->signature_statuses($rep_info, $old, $new);
        return !![grep $_ eq 'N', @$revs];
      }
    },
    {id => 'non_fast_forward', label => 'Block force pushes', default => 1,
      explain => 'Prevent users with push access from force pushing to refs',
      error => ': force push',
      check => sub () {
        my ($rep_info, $old, $new, $ref) = @_;
        return 0 unless $old && $new;
        return !!@{$git->non_fast_forward($rep_info, $old, $new)};
      }
    }
  ];
}

sub compile_ruleset_selectors {
  my ($self, $ruleset_row_id, $default_target) = @_;

  local *re = sub {
    my $re = Gitprep::Util::glob2regex(shift);
    return qr($re);
  };

  my $selectors = $self->app->dbi->model('ruleset_selector')->select(
      where => {ruleset => $ruleset_row_id}
    )->all;
  my ($all, $default, @include, @exclude);
  foreach my $selector (@$selectors) {
    my $kind = $selector->{kind};
    $default = $default_target if $kind eq 'default';
    $all = 1 if $kind eq 'all';
    CORE::push(@include, re($selector->{selector})) if $kind eq 'include';
    CORE::push(@exclude, re($selector->{selector})) if $kind eq 'exclude';
  }
  $all = 1 if !$default && !@include;
  $default = undef if $all;
  @include = () if $all;
  return {
    all => $all,
    default => $default // '',
    include => \@include,
    exclude => \@exclude
  };
}

sub ruleset_selected {
  my ($self, $compiled, $target) = @_;

  # Return whether a target is matched by a precompiled set of ruleset selectors

  my $re;
  my $selected = $compiled->{all};
  $selected = 1 if $compiled->{default} eq $target;
  foreach $re (@{$compiled->{include}}) {
    last if $selected;
    $selected = 1 if $target =~ $re;
  }
  foreach $re (@{$compiled->{exclude}}) {
    last if !$selected;
    $selected = undef if $target =~ $re;
  }
  return $selected;
}

sub emojis {
  return [
    {name => 'thumbs up', symbol => "\x{1f44d}"},
    {name => 'thumbs down', symbol => "\x{1f44e}"},
    {name => 'laugh', symbol => "\x{1f604}"},
    {name => 'hooray', symbol => "\x{1f389}"},
    {name => 'confused', symbol => "\x{1f615}"},
    {name => 'heart', symbol => "\x{2764}\x{fe0f}"},
    {name => 'rocket', symbol => "\x{1f680}"},
    {name => 'eyes', symbol => "\x{1f440}"}
  ];
}

1;
