package Gitprep::API;
use Mojo::Base -base;

use Digest::MD5 'md5_hex';
use Text::Markdown::Hoedown qw(HOEDOWN_EXT_FENCED_CODE HOEDOWN_EXT_TABLES HOEDOWN_EXT_NO_INTRA_EMPHASIS);
use Carp 'croak';
use Encode 'decode', 'encode';

has 'cntl';

sub markdown_wiki {
  my ($self, $user_id, $project_id, $content) = @_;

  my $url_base = $self->cntl->url_for("/$user_id/$project_id/wiki");
  
  my $re_cb = sub {
    my ($link_text, $title) = @_;
    
    # [[Link text|Title]]
    # [[Title]]
    if (!defined $title || !length $title) {
      $title = $link_text;
    }
    
    my $replace = "[$link_text](" . $url_base . "\/$title)";
    
    my $exists_page = $self->exists_wiki_page($user_id, $project_id, $title);
    
    unless ($exists_page) {
      $replace = '<span class="wiki-link-no-title">' . $replace . '</span>';
    }
    
    return $replace;
  };

  $content =~ s/\[\[([^\]\|]+?)(?:\|([^\[\]]+?))?\]\]/$re_cb->($1, $2)/eg;
  my $content_md = $self->markdown($content);
  
  return $content_md;
}

sub exists_wiki_page {
  my ($self, $user_id, $project_id, $title) = @_;
  
  my $wiki_work_rep_info = $self->app->wiki_work_rep_info($user_id, $project_id);
  
  # File name
  my $file_name = $title;
  $file_name =~ s/^ +//;
  $file_name =~ s/ +$//;
  $file_name .= '.md';
  
  # File abs name
  my $file_abs_name = "$wiki_work_rep_info->{work_tree}/$file_name";
  
  my $exists = -f encode('UTF-8', $file_abs_name);
  
  return $exists;
}

sub get_wiki_pages {
  my ($self, $user_id, $project_id) = @_;
  
  my $wiki_work_rep_info = $self->app->wiki_work_rep_info($user_id, $project_id);
  
  # Open directory
  my $dir = $wiki_work_rep_info->{work_tree};
  opendir my $dh, $dir
    or croak "Can't open directory \"$dir\":$!";
  
  # Pages
  my @pages;
  while (my $file = readdir $dh) {
    $file = decode('UTF-8', $file);
    next if $file =~ /^\./;
    $file =~ s/\.[^\.]+$//;
    push @pages, $file;
  }
  
  @pages = sort { lc $a cmp lc $b } @pages;
  
  return \@pages;
}

sub get_wiki_pages_count {
  my ($self, $user_id, $project_id) = @_;
  
  my $wiki_work_rep_info = $self->app->wiki_work_rep_info($user_id, $project_id);
  
  # Open directory
  my $dir = $wiki_work_rep_info->{work_tree};
  opendir my $dh, $dir
    or croak "Can't open directory \"$dir\":$!";
  
  # Pages
  my $count = 0;
  while (my $file = readdir $dh) {
    $file = decode('UTF-8', $file);
    next if $file =~ /^\./;
    $file =~ s/\.[^\.]+$//;
    $count++;
  }
  
  return $count;
}

sub get_wiki_page_content {
  my ($self, $user_id, $project_id, $title) = @_;
  
  my $wiki_work_rep_info = $self->app->wiki_work_rep_info($user_id, $project_id);
  
  # File name
  my $file_name = $title;
  $file_name =~ s/^ +//;
  $file_name =~ s/ +$//;
  $file_name .= '.md';
  
  # File abs name
  my $file_abs_name = "$wiki_work_rep_info->{work_tree}/$file_name";
  
  unless (-f encode('UTF-8', $file_abs_name)) {
    return;
  }
  
  open my $fh, '<', encode('UTF-8', $file_abs_name)
    or die "Can't open file \"" . encode('UTF-8', $file_abs_name) . "\": $!";
  
  my $content = do { local $/; <$fh> };
  
  $content = decode('UTF-8', $content);
  
  close $fh;
  
  return $content;
}

sub create_wiki_page {
  my ($self, $user_id, $project_id, $title, $content, $commit_message) = @_;
  
  # Project row id
  my $project_row_id = $self->get_project_row_id($user_id, $project_id);
  
  # Get wiki
  my $wiki = $self->app->dbi->model('wiki')->select(where => {project => $project_row_id})->one;
  
  # First wiki page
  unless ($wiki) {
    # Create wiki
    my $new_wiki = {
      project => $project_row_id
    };
    
    eval {
      $self->app->dbi->connector->txn(sub {
        $self->app->dbi->model('wiki')->insert($new_wiki);
        $self->app->manager->create_wiki_rep($user_id, $project_id);
        $self->app->manager->create_wiki_work_rep($user_id, $project_id);
      });
    };
    
    if (my $error = $@) {
      die $error
    }
  }
  
  # Update page
  my $wiki_work_rep_info = $self->app->wiki_work_rep_info($user_id, $project_id);
  my $wiki_rep_info = $self->app->wiki_rep_info($user_id, $project_id);
  
  # File name
  my $file_name = $title;
  $file_name =~ s/^ +//;
  $file_name =~ s/ +$//;
  $file_name .= '.md';
  
  # File abs name
  my $file_abs_name = "$wiki_work_rep_info->{work_tree}/$file_name";
  
  open my $fh, '>', encode('UTF-8', $file_abs_name)
    or die "Can't open file \"". encode('UTF-8', $file_abs_name) . "\": $!";
  
  # Write content to file
  print $fh $content;
  
  # Close file
  close $fh;
  
  # Check file changes
  my $is_file_change;
  {
    my @git_status_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'status',
      '-s',
      $wiki_work_rep_info->{work_tree}
    );
    open my $fh, '-|', @git_status_cmd
      or croak "Can't execute @git_status_cmd";
    my $result = <$fh>;
    
    $is_file_change = length $result ? 1 : 0;
  }
  
  # Nothing to do if files is not changed
  return unless $is_file_change;
  
  # Add
  my @git_add_cmd = $self->app->git->cmd(
    $wiki_work_rep_info,
    'add',
    $wiki_work_rep_info->{work_tree}
  );
  
  Gitprep::Util::run_command(@git_add_cmd)
    or croak "Can't execute git add: @git_add_cmd";
  
  # Commit
  my @git_commit_cmd = $self->app->git->cmd(
    $wiki_work_rep_info,
    'commit',
    '-q',
    '-m',
    $commit_message
  );
  Gitprep::Util::run_command(@git_commit_cmd)
    or croak "Can't execute git commit: @git_commit_cmd";
  
  # Push
  {
    my @git_push_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'push',
      '-q',
      $wiki_rep_info->{git_dir},
      'master'
    );
    # (This is bad, but --quiet option can't supress in old git)
    Gitprep::Util::run_command(@git_push_cmd)
      or croak "Can't execute git push: @git_push_cmd";
  }
}

sub rename_and_update_wiki_page {
  my ($self, $user_id, $project_id, $original_title, $title, $content, $commit_message) = @_;
  
  # Project row id
  my $project_row_id = $self->get_project_row_id($user_id, $project_id);
  
  # Update page
  my $wiki_work_rep_info = $self->app->wiki_work_rep_info($user_id, $project_id);
  my $wiki_rep_info = $self->app->wiki_rep_info($user_id, $project_id);
  
  # Original file name
  my $original_file_name = $original_title;
  $original_file_name =~ s/^ +//;
  $original_file_name =~ s/ +$//;
  $original_file_name .= '.md';
  
  # File name
  my $file_name = $title;
  $file_name =~ s/^ +//;
  $file_name =~ s/ +$//;
  $file_name .= '.md';

  # Original file abs name
  my $original_file_abs_name = "$wiki_work_rep_info->{work_tree}/$original_file_name";
  
  # File abs name
  my $file_abs_name = "$wiki_work_rep_info->{work_tree}/$file_name";
  
  # Create file
  open my $fh, '>', encode('UTF-8', $file_abs_name)
    or die "Can't open file \"". encode('UTF-8', $file_abs_name) . "\": $!";
  
  # Write content to file
  print $fh $content;
  
  # Close file
  close $fh;
  
  # Delete original file
  if (-f encode('UTF-8', $original_file_abs_name)) {
    unlink encode('UTF-8', $original_file_abs_name)
      or die "Can't delete file \"" . encode('UTF-8', $original_file_abs_name) . "\": $!";
  }
  
  # Check file changes
  my $is_file_change;
  {
    my @git_status_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'status',
      '-s',
      $wiki_work_rep_info->{work_tree}
    );
    open my $fh, '-|', @git_status_cmd
      or croak "Can't execute @git_status_cmd";
    my $result = <$fh>;
    
    $is_file_change = length $result ? 1 : 0;
  }
  
  # Nothing to do if files is not changed
  return unless $is_file_change;

  # Git remove
  my @git_rm_cmd = $self->app->git->cmd(
    $wiki_work_rep_info,
    'rm',
    encode('UTF-8', $original_file_abs_name)
  );
  
  Gitprep::Util::run_command(@git_rm_cmd)
    or croak "Can't execute git rm: @git_rm_cmd";
  
  # Add
  my @git_add_cmd = $self->app->git->cmd(
    $wiki_work_rep_info,
    'add',
    $wiki_work_rep_info->{work_tree}
  );
  
  Gitprep::Util::run_command(@git_add_cmd)
    or croak "Can't execute git add: @git_add_cmd";

  # Commit
  my @git_commit_cmd = $self->app->git->cmd(
    $wiki_work_rep_info,
    'commit',
    '-q',
    '-m',
    $commit_message
  );
  Gitprep::Util::run_command(@git_commit_cmd)
    or croak "Can't execute git commit: @git_commit_cmd";
  
  # Push
  {
    my @git_push_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'push',
      '-q',
      $wiki_rep_info->{git_dir},
      'master'
    );
    # (This is bad, but --quiet option can't supress in old git)
    Gitprep::Util::run_command(@git_push_cmd)
      or croak "Can't execute git push: @git_push_cmd";
  }
}

sub delete_wiki_page {
  my ($self, $user_id, $project_id, $title) = @_;
  
  # Project row id
  my $project_row_id = $self->get_project_row_id($user_id, $project_id);
  
  # Get wiki
  my $wiki = $self->app->dbi->model('wiki')->select(where => {project => $project_row_id})->one;
  
  # Wiki working directory
  my $wiki_work_rep_info = $self->app->wiki_work_rep_info($user_id, $project_id);
  
  # Wiki repository
  my $wiki_rep_info = $self->app->wiki_rep_info($user_id, $project_id);
  
  # File name
  my $file_name = $title;
  $file_name .= '.md';
  
  # File abs name
  my $file_abs_name = "$wiki_work_rep_info->{work_tree}/$file_name";
  
  # Delete file
  if (-f encode('UTF-8', $file_abs_name)) {
    unlink encode('UTF-8', $file_abs_name)
      or die "Can't delete file \"" . encode('UTF-8', $file_abs_name) . "\": $!";
  }
  
  # Check file changes
  my $is_file_change;
  {
    my @git_status_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'status',
      '-s',
      $wiki_work_rep_info->{work_tree}
    );
    open my $fh, '-|', @git_status_cmd
      or croak "Can't execute @git_status_cmd";
    my $result = <$fh>;
    
    $is_file_change = length $result ? 1 : 0;
  }
  
  # Nothing to do if files is not changed
  return unless $is_file_change;
  
  # Git remove
  my @git_rm_cmd = $self->app->git->cmd(
    $wiki_work_rep_info,
    'rm',
    encode('UTF-8', $file_abs_name)
  );
  
  Gitprep::Util::run_command(@git_rm_cmd)
    or croak "Can't execute git rm: @git_rm_cmd";
  
  # Commit
  my $commit_message = "Deleted $title";
  my @git_commit_cmd = $self->app->git->cmd(
    $wiki_work_rep_info,
    'commit',
    '-q',
    '-m',
    encode('UTF-8', $commit_message)
  );
  Gitprep::Util::run_command(@git_commit_cmd)
    or croak "Can't execute git commit: @git_commit_cmd";
  
  # Push
  {
    my @git_push_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'push',
      '-q',
      $wiki_rep_info->{git_dir},
      'master'
    );
    # (This is bad, but --quiet option can't supress in old git)
    Gitprep::Util::run_command(@git_push_cmd)
      or croak "Can't execute git push: @git_push_cmd";
  }
}

sub get_pull_request_count {
  my ($self, $user_id, $project_id, $opt) = @_;
  
  $opt ||= {};
  
  my $project_row_id = $self->get_project_row_id($user_id, $project_id);
  
  my $where = $self->app->dbi->where;
  my $clause = ['and', 'pull_request <> 0', ':project{=}'];
  my $param = {project => $project_row_id};
  
  # Open
  if (exists $opt->{open}) {
    push @$clause, ':issue.open{=}';
    $param->{'issue.open'} = $opt->{open};
  }
  
  $where->clause($clause);
  $where->param($param);
  
  my $pull_request_count = $self->app->dbi->model('issue')->select(
    'count(*)',
    where => $where
  )->value;
  
  return $pull_request_count;
}

sub get_open_pull_request_count {
  my ($self, $user_id, $project_id) = @_;
  
  return $self->get_pull_request_count($user_id, $project_id, {open => 1});
}

sub get_close_pull_request_count {
  my ($self, $user_id, $project_id) = @_;
  
  return $self->get_pull_request_count($user_id, $project_id, {open => 0});
}

sub get_issue_count {
  my ($self, $user_id, $project_id, $opt) = @_;
  
  $opt ||= {};

  my $project_row_id = $self->get_project_row_id($user_id, $project_id);
  
  my $where = $self->app->dbi->where;
  my $clause = ['and', 'pull_request = 0', ':project{=}'];
  my $param = {project => $project_row_id};
  
  # Open
  if (exists $opt->{open}) {
    push @$clause, ':issue.open{=}';
    $param->{'issue.open'} = $opt->{open};
  }
  
  $where->clause($clause);
  $where->param($param);

  my $issue_count = $self->app->dbi->model('issue')->select(
    'count(*)',
    where => $where
  )->value;
  
  return $issue_count;
}

sub get_open_issue_count {
  my ($self, $user_id, $project_id) = @_;
  
  return $self->get_issue_count($user_id, $project_id, {open => 1});
}

sub get_close_issue_count {
  my ($self, $user_id, $project_id) = @_;
  
  return $self->get_issue_count($user_id, $project_id, {open => 0});
}

sub api_update_issue_message {
  my ($self, $issue_message_row_id, $message, $user_id) = @_;
  
  my $issue_message = $self->app->dbi->model('issue_message')->select(
    {user => ['id']}, where => {'issue_message.row_id' => $issue_message_row_id}
  )->one;
  
  my $session_user_id = $self->session_user_id;

  my $is_my_project = $user_id eq $session_user_id;
  my $is_my_comment = $issue_message->{'user.id'} eq $session_user_id;
  my $can_modify = $is_my_project || $is_my_comment;
  
  my $json;
  if ($can_modify) {
    my $now_tm = Time::Moment->now;
    my $update_time = $now_tm->epoch;
    $self->app->log->info($update_time);
    
    $self->app->dbi->model('issue_message')->update(
      {
        message => $message,
        update_time => $update_time
      },
      where => {row_id => $issue_message_row_id}
    );
    
    my $markdown_message = $self->markdown($message);
    
    $json = {
      success => 1,
      markdown_message => $markdown_message
    };
  }
  else {
    $json = {success => 0};
  }
  
  return $json;
}

sub api_delete_issue_message {
  my ($self, $issue_message_row_id, $user_id) = @_;
  
  my $issue_message = $self->app->dbi->model('issue_message')->select(
    {user => ['id']}, where => {'issue_message.row_id' => $issue_message_row_id}
  )->one;
  
  my $session_user_id = $self->session_user_id;

  my $is_my_project = $user_id eq $session_user_id;
  my $is_my_comment = $issue_message->{'user.id'} eq $session_user_id;
  my $can_modify = $is_my_project || $is_my_comment;
  
  my $json;
  if ($can_modify) {
    $self->app->dbi->model('issue_message')->delete(
      where => {row_id => $issue_message_row_id}
    );
    
    $json = {success => 1};
  }
  else {
    $json = {success => 0};
  }
  
  return $json;
}

sub add_issue_message {
  my ($self, $user_id, $project_id, $number, $message) = @_;
  
  $self->app->dbi->connector->txn(sub {
    my $issue_row_id = $self->app->dbi->model('issue')->select(
      'issue.row_id',
      where => {
        'project__user.id' => $user_id,
        'project.id' => $project_id,
        number => $number
      }
    )->value;

    # Issue message number
    my $issue_message_number = $self->app->dbi->model('issue_message')->select(
      'max(number)',
      where => {issue => $issue_row_id}
    )->value;
    $issue_message_number++;

    # New issue message
    my $now_tm = Time::Moment->now_utc;
    my $now_epoch = $now_tm->epoch;
    my $session_user_row_id = $self->session_user_row_id;
    my $new_issue_message = {
      issue => $issue_row_id,
      number => $issue_message_number,
      message => $message,
      create_time => $now_epoch,
      update_time => $now_epoch,
      user => $session_user_row_id
    };
    
    $self->app->dbi->model('issue_message')->insert($new_issue_message);
  });
}

sub markdown {
  my ($self, $markdown_text) = @_;

  # Remove script tags
  $markdown_text =~ s/\<\s*script\s*.*?\>//g;
  $markdown_text =~ s/\<\s*\/\s*script\s*.*?\>//g;

  my $html_text = Text::Markdown::Hoedown::markdown(
    $markdown_text, extensions => HOEDOWN_EXT_FENCED_CODE|HOEDOWN_EXT_TABLES|HOEDOWN_EXT_NO_INTRA_EMPHASIS
  );
  
  return $html_text;
}

sub age_string {
  my ($self, $epoch_time) = @_;
  
  my $age = time - $epoch_time;
  
  my $age_string = $self->cntl->app->git->_age_string($age);
  
  return $age_string;
}

sub get_user_row_id {
  my ($self, $user_id) = @_;
  
  my $user_row_id = $self->app->dbi->model('user')->select('row_id', where => {id => $user_id})->value;
  
  return $user_row_id;
}

sub get_project_row_id {
  my ($self, $user_id, $project_id) = @_;
  
  my $user_row_id = $self->app->dbi->model('user')->select('row_id', where => {id => $user_id})->value;
  my $project_row_id = $self->app->dbi->model('project')->select(
    'row_id',
    where => {user => $user_row_id, id => $project_id}
  )->value;
  
  return $project_row_id;
}

sub app { shift->cntl->app }

sub encrypt_password {
  my ($self, $password) = @_;
  
  my $salt;
  $salt .= int(rand 10) for (1 .. 40);
  my $password_encryped = md5_hex md5_hex "$salt$password";
  
  return ($password_encryped, $salt);
}

sub check_password {
  my ($self, $password, $salt, $password_encrypted) = @_;
  
  return unless defined $password && $salt && $password_encrypted;
  
  return md5_hex(md5_hex "$salt$password") eq $password_encrypted;
}

sub check_user_and_password {
  my ($self, $user_id, $password) = @_;
  
  my $row
    = $self->app->dbi->model('user')->select(['password', 'salt'], where => {id => $user_id})->one;
  
  return unless $row;
  
  my $is_valid = $self->check_password(
    $password,
    $row->{salt},
    $row->{password}
  );
  
  return $is_valid;
}

sub is_collaborator {
  my ($self, $collaborator_id, $user_id, $project_id) = @_;
  
  my $user_row_id = $self->get_user_row_id($user_id);
  my $project_row_id = $self->app->dbi->model('project')->select(
    where => {user => $user_row_id, id => $project_id}
  )->value;
  my $collaborator_row_id = $self->get_user_row_id($collaborator_id);
  
  my $row = $self->app->dbi->model('collaboration')->select(
    where => {project => $project_row_id, user => $collaborator_row_id}
  )->one;
  
  return $row ? 1 : 0;
}

sub can_access_private_project {
  my ($self, $user_id, $project_id) = @_;

  my $session_user_row_id = $self->cntl->session('user_row_id');
  return unless defined $session_user_row_id;
  
  my $session_user_id = $self->app->dbi->model('user')->select(
    'id', where => {row_id => $session_user_row_id}
  )->value;
  
  my $is_valid =
    ($user_id eq $session_user_id || $self->is_collaborator($session_user_id, $user_id, $project_id))
    && $self->logined;
  
  return $is_valid;
}

sub can_write_access {
  my ($self, $session_user_id, $user_id, $project_id) = @_;
  
  return unless $session_user_id;
  
  my $can_write_access
    = length $session_user_id &&
    (
      $session_user_id eq $user_id
      || $self->is_collaborator($session_user_id, $user_id, $project_id)
    );
  
  return $can_write_access;
}

sub new {
  my ($class, $cntl) = @_;

  my $self = $class->SUPER::new(cntl => $cntl);
  
  return $self;
}

sub logined_admin {
  my $self = shift;

  # Controler
  my $c = $self->cntl;
  
  # Check logined as admin
  my $session_user_id = $self->session_user_id;
  
  return $self->app->manager->is_admin($session_user_id) && $self->logined($session_user_id);
}

sub session_user_row_id {
  my $self = shift;
  
  my $session_user_row_id = $self->cntl->session('user_row_id');
  
  return $session_user_row_id;
}

sub session_user_id {
  my $self = shift;
  
  my $session_user_row_id = $self->cntl->session('user_row_id');
  my $session_user_id = $self->app->dbi->model('user')->select(
    'id', where => {row_id => $session_user_row_id}
  )->value;
  
  return $session_user_id;
}

sub logined {
  my ($self, $user_id) = @_;
  
  my $c = $self->cntl;
  my $dbi = $c->app->dbi;
  
  my $session_user_row_id = $c->session('user_row_id');
  my $session_user_id = $self->session_user_id;
  my $password = $c->session('password');
  return unless defined $password;
  
  my $correct_password = $dbi->model('user')->select(
    'password',
    where => {row_id => $session_user_row_id}
  )->value;
  return unless defined $correct_password;
  
  my $logined;
  if (defined $user_id) {
    $logined = $user_id eq $session_user_id && $password eq $correct_password;
  }
  else {
    $logined = $password eq $correct_password
  }
  
  return $logined;
}

sub params {
  my $self = shift;
  
  my $c = $self->cntl;
  
  my %params;
  for my $name ($c->param) {
    my @values = $c->param($name);
    if (@values > 1) {
      $params{$name} = \@values;
    }
    elsif (@values) {
      $params{$name} = $values[0];
    }
  }
  
  return \%params;
}

1;

