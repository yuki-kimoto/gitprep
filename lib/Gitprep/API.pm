package Gitprep::API;
use Mojo::Base -base;

use Digest::MD5 'md5_hex';
use Text::Markdown::Hoedown qw(HOEDOWN_EXT_FENCED_CODE HOEDOWN_EXT_TABLES HOEDOWN_EXT_NO_INTRA_EMPHASIS);
use HTML::FormatText::WithLinks;
use MIME::Entity;

use Carp 'croak';
use Encode 'decode', 'encode';

has 'cntl';

sub markdown_wiki {
  my ($self, $user_id, $project_id, $content) = @_;

  my $url_base = $self->cntl->url_for("/$user_id/$project_id/wiki");
  
  local *re_cb = sub {
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

  $content =~ s/\[\[([^\]\|]+?)(?:\|([^\[\]]+?))?\]\]/re_cb($1, $2)/eg;
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
  
  open my $fh, '>:encoding(UTF-8)', encode('UTF-8', $file_abs_name)
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
  open my $fh, '>:encoding(UTF-8)', encode('UTF-8', $file_abs_name)
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

sub get_issue_count {
  my ($self, $user_id, $project_id, $opt) = @_;
  
  $opt ||= {};

  my $project_row_id = $self->get_project_row_id($user_id, $project_id);
  
  my $where = $self->app->dbi->where;
  my $clause = ['and', ':project{=}'];
  my $param = {project => $project_row_id};

  # Issue kind.
  if (exists $opt->{pull}) {
    push @$clause, $opt->{pull}? 'pull_request <> 0': 'pull_request = 0';
  }
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
  
  return $self->get_issue_count($user_id, $project_id, {pull => 0, open => 1});
}

sub get_open_pull_request_count {
  my ($self, $user_id, $project_id) = @_;
  
  return $self->get_issue_count($user_id, $project_id, {pull => 1, open => 1});
}

sub api_update_issue_message {
  my ($self, $issue_message_row_id, $message, $user_id) = @_;
  
  my $issue_message = $self->app->dbi->model('issue_message')->select(
    {user => ['id']}, where => {'issue_message.row_id' => $issue_message_row_id}
  )->one;

  my $json = {success => 0};
  my $session_user_id = $self->session_user_id;

  if ($session_user_id) {
    my $is_my_project = $user_id eq $session_user_id;
    my $is_my_comment = $issue_message->{'user.id'} eq $session_user_id;
    my $can_modify = $is_my_project || $is_my_comment;

    if ($can_modify) {
      my $update_time = $self->now;
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
  }

  return $json;
}

sub api_delete_issue_message {
  my ($self, $issue_message_row_id, $user_id) = @_;
  
  my $issue_message = $self->app->dbi->model('issue_message')->select(
    {user => ['id']}, where => {'issue_message.row_id' => $issue_message_row_id}
  )->one;

  my $json = {success => 0};
  my $session_user_id = $self->session_user_id;

  if ($session_user_id) {
    my $is_my_project = $user_id eq $session_user_id;
    my $is_my_comment = $issue_message->{'user.id'} eq $session_user_id;
    my $can_modify = $is_my_project || $is_my_comment;

    if ($can_modify) {
      $self->app->dbi->model('issue_message')->delete(
        where => {row_id => $issue_message_row_id}
      );

      $json = {success => 1};
    }
  }

  return $json;
}

sub add_issue_message {
  my ($self, $user_id, $project_id, $number, $message) = @_;
  my $issue_message_number;
  
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
    $issue_message_number = $self->app->dbi->model('issue_message')->select(
      'max(number)',
      where => {issue => $issue_row_id}
    )->value;
    $issue_message_number++;

    # New issue message
    my $now_epoch = $self->now;
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

  return $issue_message_number;
}

sub markdown {
  my ($self, $markdown_text) = @_;

  my $html_text = Text::Markdown::Hoedown::markdown(
    $markdown_text, extensions => HOEDOWN_EXT_FENCED_CODE|HOEDOWN_EXT_TABLES|HOEDOWN_EXT_NO_INTRA_EMPHASIS
  );
  
  require HTML::Restrict; # For compilation performance
  my $hr = HTML::Restrict->new(
    rules => {
      h1 => [qw( id class )],
      h2 => [qw( id class )],
      h3 => [qw( id class )],
      h4 => [qw( id class )],
      h5 => [qw( id class )],
      h6 => [qw( id class )],
      p => [qw( id class align )],
      div => [qw( id class )],
      span => [qw( id class )],
      br => [qw( class / )],
      em => [qw( class )],
      strong => [qw( class )],
      code => [qw( id class )],
      pre => [qw( id class )],
      tt => [qw( id class )],
      kbd => [qw( class )],
      del => [qw( id class cite datetime )],
      hr => [qw( class / )],
      ul => [qw( class )],
      ol => [qw( class )],
      dl => [qw( class )],
      dt => [qw( class )],
      dd => [qw( class )],
      li => [qw( class )],
      a => [qw( href id class )],
      img => [qw( src alt title align id class width height / )],
      blockquote => [qw( id class )],
      table => [qw( id class border width bgcolor cellspacing )],
      th => [qw( class rowspan colspan bgcolor align valign )],
      tr => [qw( class rowspan colspan bgcolor align valign )],
      td => [qw( class rowspan colspan bgcolor align valign )],
      thead => [qw( class bgcolor align valign )],
      tbody => [qw( class bgcolor align valign )],
      tfoot => [qw( class bgcolor align valign )],
      caption => [qw( class align valign )],
      col => [qw( class align valign )],
      colgroup => [qw( class align valign )],
      sup => [qw( class )],
      sub => [qw( class )],
      b => [qw( class )],
      i => [qw( class )],
      u => [qw( class )],
      s => [qw( class )],
      strike => [qw( class )]
    }
  );

  $html_text = $hr->process($html_text);

  return $html_text;
}

sub mentioned {
  my ($self, $message) = @_;
  my %users;

  # Scan message for @<username>s and return an array of them.

  while ($message =~ /@([a-zA-Z0-9_\-]+)/g) {
    $users{$1} = 1;
  }
  my @result = keys %users;
  return @result;
}

sub ssh_rep_url {
  my ($self, $user_id, $repository) = @_;

  my $app = $self->app;
  my $user = $app->config->{basic}{ssh_user} || getpwuid($>);
  my $port = $app->config->{basic}{ssh_port};
  my $home = $app->config->{basic}{'ssh_rep_url_base'} || $app->rep_home;
  my $url = "$user@" . $self->cntl->url_for->to_abs->host;

  if (!$app->config->{basic}{scp_url} || $port) {
    # True ssh url.
    $url .= ":$port" if $port;
    return "ssh://$url$home/$user_id/$repository.git";
  }

  # scp-like pseudo-url.
  my (undef, undef, undef, undef, undef, undef, undef, $userdir) = getpwnam($user);
  # If home is a subdirectory of the git user's one, use relative path.
  $home = "~$1" if $userdir && $home =~ m#^\Q$userdir\E(/.*|)$#;
  $home = [map $_ ne ''? $_: (), split('/', $home)];
  my $first = shift @$home;
  unshift @$home, "/$first" unless $first eq '~';
  push @$home, ($user_id, "$repository.git");
  return "$url:" . join '/', @$home;
}

sub DOM_element {
  my $self = shift;
  my $tag = shift;

  my $child;
  $child = pop if @_ % 2 && 'Mojo::DOM' eq ref $_[-1];
  my $element = Mojo::DOM->new_tag($tag, @_);
  $element = $element->child_nodes->first;
  $element->append_content($child) if $child;
  return $element;
}

sub DOM_text {
  my ($self, $text) = @_;

  # Helper to get an orphan DOM text node.
  my $span = $self->DOM_element('span', $text);
  return $span->child_nodes->first;
}

sub DOM_add_class {
  my $self = shift;
  my $dom = shift;

  return unless $dom;

  my $attrs = $dom->attr;
  my @classes;
  unshift @_, ($attrs->{class} || '');
  push @classes, split /\s+/, $_ for (@_);
  my %unique = map {$_ => 1} @classes;
  delete $unique{''};
  $attrs->{class} = join ' ', keys %unique;
}

sub DOM_set_class {
  my $self = shift;
  my $dom = $_[0];

  return unless $dom;
  my $attrs = $dom->attr;
  delete $attrs->{class};
  $self->DOM_add_class(@_);
}

sub DOM_remove_class {
  my $self = shift;
  my $dom = shift;

  return unless $dom;

  my $attrs = $dom->attr;
  my @classes = split /\s+/, ($attrs->{class} || '');
  my %unique = (@classes => @classes);
  for (@_) {
    delete $unique{$_} for (split /\s+/, $_);
  }
  delete $unique{''};
  $attrs->{class} = join ' ', keys %unique;
}

sub DOM_render {
  my ($self, $dom) = @_;
  return Mojo::ByteStream->new($dom);
}

sub now {
  require Time::Moment; # For compilation performance
  return Time::Moment->now_utc->epoch;
}

sub strftime {
  
  require Time::Moment; # For compilation performance
  
  my ($self, $unixtime, $format, $offset_minutes) = @_;
  
  my $tm = Time::Moment->from_epoch($unixtime);
  $tm = $tm->with_offset_same_instant($offset_minutes) if $offset_minutes;
  return Time::Moment->from_epoch($unixtime)->strftime($format || '%F %T');
}

sub _age_ago {
  my($self,$unit,$age) = @_;

  return $age . " $unit" . ( $unit =~ /^(sec|min)$/ ? "" : ( $age > 1 ? "s" : "" ) ) . " ago";
}

sub _age_string {
  my ($self, $age) = @_;
  my $age_str;

  if ($age >= 60 * 60 * 24 * 365) {
    $age_str = $self->_age_ago(year => (int $age/60/60/24/365));
  } elsif ($age >= 60 * 60 * 24 * (365/12)) {
    $age_str = $self->_age_ago(month => int $age/60/60/24/(365/12));
  } elsif ($age >= 60 * 60 * 24 * 7) {
    $age_str = $self->_age_ago(week => int $age/60/60/24/7);
  } elsif ($age >= 60 * 60 * 24) {
    $age_str = $self->_age_ago(day => int $age/60/60/24);
  } elsif ($age >= 60 * 60) {
    $age_str = $self->_age_ago(hour => int $age/60/60);
  } elsif ($age >= 60) {
    $age_str = $self->_age_ago(min => int $age/60);
  } elsif ($age >= 1) {
    $age_str = $self->_age_ago(sec => int $age);
  } else {
    $age_str .= 'right now';
  }

  $age_str =~ s/^1 /a /;
  $age_str =~ s/^a hour/an hour/;
  
  return $age_str;
}

sub age_string {
  my ($self, $epoch) = @_;

  return $self->_age_string($self->now - $epoch);
}

sub time_tooltip_element {
  my $self = shift;
  my $unixtime = shift;
  my %attrs = (
    tag => 'span',
    @_
  );

  # Default tooltip to UTC.
  if ($unixtime) {
    $attrs{title} ||= $self->strftime($unixtime, $attrs{format});
    $attrs{onmouseover} = "Gitprep.dateTooltip(this, $unixtime)";
  }

  my $tag = delete $attrs{tag};
  return $self->DOM_element($tag, %attrs);
}

sub age_element {
  my $self = shift;
  my $unixtime = shift;
  my $age = $unixtime? $self->age_string($unixtime): 'sometime';
  my $element = $self->time_tooltip_element($unixtime, @_);
  $element->content($self->DOM_text($age));
  return $self->DOM_render($element);
}

sub load_svg {
  my $self = shift;
  my $name = shift;
  my %args = (@_);

  open my $fh, '<', $self->app->home . "/$name" or return undef;
  read $fh, my $markup, -s $fh;
  close $fh;
  my $dom = Mojo::DOM->new($markup);
  return undef unless $dom;
  my $svg = $dom->find('svg')->first;
  return undef unless $svg;
  my $attrs = $svg->attr;
  delete $attrs->{xmlns};

  my ($width, $height) = ($attrs->{width}, $attrs->{height});
  my ($w, $h) = ($width, $height);
  my $viewbox = $attrs->{viewBox} || $attrs->{viewbox};
  unless ($viewbox) {
    $viewbox = "0 0 $w $h" if $w && $h;
  }
  $attrs->{viewBox} = $viewbox if $viewbox;
  delete $attrs->{viewbox};
  if ($viewbox =~ /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s"$/) {
    $w = $3 - $1 unless defined $w;
    $h = $4 - $2 unless defined $h;
  }

  $width = delete $args{width} if $args{width};
  $height = delete $args{height} if $args{height};
  $attrs->{width} = $width if $width;
  $attrs->{height} = $height if $height;

  my $class = delete $args{class};
  my $title = delete $args{title};
  my $style = delete $args{style};
  my $tag = delete $args{tag};
  $attrs->{$_} = $args{$_} for (keys %args);
  $self->DOM_add_class($svg, $class) if defined $class;

  $style = 'width:fit-content;height:fit-content;' . ($style || '') if $w && $width && $h && $height && ($width != $w || $height != $h);
  %args = ();
  $args{style} = $style if $style;
  $args{title} = $title if $title;
  $svg = $self->DOM_element($tag || 'span', %args, $svg) if keys %args;
  return $svg;
}

sub load_icon {
  my $self = shift;
  my $name = shift;
  my $icon;

  for my $place (
    ['', ''],
    ['octicons/', ''],
    ['octicons/', '-16'],
    ['octicons/', '-24'],
    ['octicons/', '-12']
  ) {
    $icon = $self->load_svg("svg/$place->[0]$name$place->[1]", @_) ||
      $self->load_svg("svg/$place->[0]$name$place->[1].svg", @_);
    last if $icon;
  }
  $self->DOM_add_class($icon, "icon icon-$name") if $icon;
  return $icon;
}

sub icon {
  my $self = shift;

  return $self->DOM_render($self->load_icon(@_));
}

sub RGBtoHSL {
  my ($self, $r, $g, $b) = @_;

  $r /= 255;
  $g /= 255;
  $b /= 255;

  my $min = $r;
  $min = $g if $min > $g;
  $min = $b if $min > $b;

  my $max = $r;
  $max = $g if $max < $g;
  $max = $b if $max < $b;

  my $h = ($min + $max) / 2;
  my $s = $h;
  my $l = $h;

  my $d = $max - $min;
  if (!$d) {
    $h = $s = 0;
  } else {
    $s = $min + $max;
    $s = $l > 0.5? $d / (2 - $s): $d / $s;

    if ($max == $r) {
      $h = ($g - $b) / $d + ($g < $b? 6: 0);
    } elsif ($max == $g) {
      $h = ($b - $r) / $d + 2;
    } else {
      $h = ($r - $g) / $d + 4;
    }
    $h /= 6;
  }

  return [360 * $h, 100 * $s, 100 * $l];
}

sub label {
  my $self = shift;
  my $label_row_id = shift;
  my %args = (@_);

  my $tag = delete $args{tag} || 'li';
  my $icon = delete $args{icon};
  my $label = $self->app->dbi->model('label')->select(['id', 'description', 'color'],
    where => {row_id => $label_row_id}
  )->one;
  $label = {id => '?', description => '! Label does not exist !', color => '#ff0000'} unless $label;
  my @nodes;
  push @nodes, $self->icon($icon || 'tag', class => 'label-icon') if defined $icon;
  push @nodes, $self->DOM_element('span', class => 'label-id', $label->{id});
  my $background = $label->{color};
  my $foreground = '#000000';
  if ($background =~ /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i) {
    my @rgb = (hex($1), hex($2), hex($3));
    $foreground = '#ffffff' if $self->RGBtoHSL(@rgb)->[2] < 52;
  }
  $args{style} = ($args{style} || '') .
    " ; background: $background; color: $foreground; fill: $foreground;";
  $args{title} = $label->{description} if $label->{description};
  my $dom = $self->DOM_element($tag, %args);
  $dom->append_content($_) for (@nodes);
  $self->DOM_add_class($dom, 'label');
  return $self->DOM_render($dom);
}

sub plural {
  my ($self, $word, $count, $prepend, $plural) = @_;

  # Return plural of `word'.
  # If `count' is 1, keep singular form.
  # If `prepend' is given, prepend it to result when `count' = 0 else `count'.
  # `plural' can be used if the plural form of `word' is irregular.

  my $prefix = '';
  if (defined($count) && defined($prepend)) {
    $prefix = $prepend;
    $prefix = $count if $count || !$prepend;
    return $prefix unless $word;
    $prefix .= ' ';
  }
  return $word unless $word;
  return "$prefix$word" unless ($count // 0) != 1;
  return "$prefix$plural" if $plural;
  $word =~ s/[ei]s$/es/ && return "$prefix$word";
  $word =~ s/(o|s|x|z|ch|sh)$/$1es/ && return "$prefix$word";
  $word =~ s/([^aeiouy])y$/$1ies/ && return "$prefix$word";
  return "$prefix${word}s";
}

sub subscribe {
  my ($self, $user_id, $issue, $reason) = @_;

  my $r = $self->app->dbi->model('subscription')->select('reason',
      where => {
        user => $user_id,
        issue => $issue
      }
    )->value;

  if (!defined $r) {
      $self->app->dbi->model('subscription')->insert(
        {
          user => $user_id,
          issue => $issue,
          reason => $reason
        }
      );
    }
  elsif ($reason ne $r) {
    if ($r eq 'U' || $reason eq 'U') {
      $self->app->dbi->model('subscription')->update(
        {
          reason => $reason,
        },
        where => {
          user => $user_id,
          issue => $issue
        }
      );
    }
  }
}

sub subscribe_mentioned {
  my ($self, $issue_row_id, $message) = @_;
  my @mentioned = $self->mentioned($message);

  if (@mentioned != 0) {
    my $results = $self->app->dbi->model('user')->select('row_id',
             where => {
               id => @mentioned
             })->all;

    for my $user_row_id (@$results) {
      $self->subscribe($user_row_id->{row_id}, $issue_row_id, 'M');
    }
  }
}

sub notify_subscribed {
  
  require Email::Sender::Simple; # For compilation performance
  
  my ($self, $user, $project, $title, $sender_row_id, $message, $message_id,
      $path_suffix, $issue_row_id) = @_;

  $self->app->{mailtransport} || return;

  # Subscriptions.
  my $subscriptions = $self->app->dbi->model('subscription')->select(
    ['subscription__user.email', 'reason'],
    where => $self->app->dbi->where(
      clause => ['and', ':user{!=}', ':issue{=}'],
      param => {user => $sender_row_id, issue => $issue_row_id}
    ))->all;

  # Watchers.
  my $watchers = $self->app->dbi->model('watch')->select(
    ['watch__user.email'],
    where => $self->app->dbi->where(
      clause => ['and', ':user{!=}', ':project{=}'],
      param => {
        user => $sender_row_id,
        project => $self->get_project_row_id($user, $project)
      }
    ))->all;

  # Merge results.
  my %recipients = ((map {$_->{email} => 'W'} @$watchers),
                    (map {$_->{email} => $_->{reason}} @$subscriptions));

  # Filter out unsubscribed.
  my @recipients = grep {$recipients{$_} ne 'U';} keys(%recipients);

  # Sender name.
  my $sender_name = $self->app->dbi->model('user')->select('name',
    where => {
      row_id => $sender_row_id
    })->value;

  # Convert markdown message to HTML.
  $message = $self->markdown($message);

  # HTML to plain text converter.
  my $html2plain = HTML::FormatText::WithLinks->new(
    before_link => '',
    after_link => ' [%l]',
    footnote => '',
    anchor_links => 0,
    skip_linked_urls => 1
  );

  # Build visible sender and recipient email addresses.
  my $conf = $self->app->config->{mail};
  my $from = "$sender_name <$conf->{from}>";
  my $to = 'undisclosed-recipients:;';
  $to = "$user/$project <$conf->{to}>" if $conf->{to};

  # Avoid multi-recipient mails as sent data can be personalized.
  for my $email (@recipients) {
    my $html = $self->cntl->render_to_string('/api/notify',
      user => $user,
      project => $project,
      path_suffix => $path_suffix,
      message => $message,
      message_id => $message_id
    )->to_string;
    my $plain = $html2plain->parse($html);
    my $top = MIME::Entity->build(From => $from,
                                  To => $to,
                                  Subject => "[$user/$project] $title",
                                  Type => 'multipart/alternative',
                                  'X-Mailer' => undef
    );
    $top->attach(Type => 'text/html',
                 Charset => 'UTF-8',
                 Data => encode('UTF-8', $html)
    );
    $top->attach(Type => 'text/plain',
                 Charset => 'UTF-8',
                 Data => encode('UTF-8', $plain)
    );
    Email::Sender::Simple->send(
      $top->stringify,
      {
        transport => $self->app->{mailtransport},
        from => $conf->{from},
        to => $email
      }
    );
  }
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

