package Gitprep::API;
use Mojo::Base -base;

use Digest::MD5 'md5_hex';
use Text::Markdown::Hoedown qw(HOEDOWN_EXT_FENCED_CODE HOEDOWN_EXT_TABLES HOEDOWN_EXT_NO_INTRA_EMPHASIS);
use HTML::FormatText::WithLinks;
use MIME::Entity;
use Email::Sender::Simple;
use Time::Moment;
use HTML::Restrict;

use Carp 'croak';
use Encode 'decode', 'encode';

use Gitprep::Repository;

has 'cntl';

# Replace title characters that have a special meaning in file names and/or URL.
sub wiki_safe_title {
  my ($self, $title) = @_;

  $title =~ s/^(.*?)\s*$/$1/; # Trim right.
  $title =~ s/^\./\x{2024}/;  # No hidden page: use one dot leader.
  $title =~ s#/#\x{2215}#g;   # Use division slashes.
  return $title;
}

sub sync_wiki_work {
  my ($self, $wiki_rep_info) = @_;
  my $wiki_work_rep_info = $wiki_rep_info->work;

  $self->app->manager->create_wiki_work_rep($wiki_rep_info)
    unless -d $wiki_work_rep_info->root;

  if (-f $wiki_rep_info->git_dir('refs/heads/master')) {
    $self->app->manager->set_remote($wiki_work_rep_info,
                                    'origin', $wiki_rep_info);
    my @git_pull_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'pull',
      $wiki_rep_info->git_dir
    );

    Gitprep::Util::run_command(@git_pull_cmd)
      or croak "Can't execute git pull: @git_pull_cmd";
  }
}

sub wiki_file_exists {
  my ($self, $rep_info, $file_name) = @_;

  my $wiki_work_rep_info = $rep_info->wiki->work;
  return -f encode('UTF-8', $wiki_work_rep_info->work_tree($file_name));
}

sub wiki_page_exists {
  my ($self, $rep_info, $title) = @_;

  return $self->wiki_file_exists($rep_info, "$title.md");
}

sub get_wiki_pages {
  my ($self, $rep_info) = @_;

  my $wiki_work_rep_info = $rep_info->wiki->work;

  # Open directory
  my $dir = $wiki_work_rep_info->work_tree;
  opendir my $dh, $dir
    or croak "Can't open directory \"$dir\":$!";

  # Pages
  my @pages;
  while (my $fn = readdir $dh) {
    $fn = decode('UTF-8', $fn);
    next if $fn =~ /^\./;
    next unless $fn =~ /^(.*)\.md$/;
    next if $self->wiki_safe_title($1) ne $1;

    # Can be a non-regular file.
    push @pages, $1 if -f encode('UTF-8', $wiki_work_rep_info->work_tree($fn));
  }

  @pages = sort { lc $a cmp lc $b } @pages;
  return \@pages;
}

sub get_wiki_page_content {
  my ($self, $rep_info, $title) = @_;

  my $wiki_work_rep_info = $rep_info->wiki->work;

  # File name
  my $file_name = "$title.md";

  # File abs name
  my $file_abs_name = $wiki_work_rep_info->work_tree($file_name);

  my $utf8_name = encode('UTF-8', $file_abs_name);
  return unless -f $utf8_name;

  open my $fh, '<', $utf8_name
    or die "Can't open file \"$utf8_name\": $!";

  my $content = do { local $/; <$fh> };

  $content = decode('UTF-8', $content);

  close $fh;

  return $content;
}

sub create_wiki_page {
  my ($self, $rep_info, $title, $content, $commit_message) = @_;
  my $wiki_rep_info = $rep_info->wiki;

  # Create wiki if not yet done.
  $self->app->manager->create_wiki_rep($wiki_rep_info)
    unless -d $wiki_rep_info->root;
  $self->sync_wiki_work($wiki_rep_info);

  # Update page
  my $wiki_work_rep_info = $wiki_rep_info->work;

  # File name
  my $file_name = "$title.md";

  # File abs name
  my $file_abs_name = $wiki_work_rep_info->work_tree($file_name);
  my $utf8_name = encode('UTF-8', $file_abs_name);

  open my $fh, '>:encoding(UTF-8)', $utf8_name
    or die "Can't open file \"$utf8_name\": $!";

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
      $wiki_work_rep_info->work_tree
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
    $wiki_work_rep_info->work_tree
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

  $self->app->manager->set_remote($wiki_work_rep_info, 'origin', $wiki_rep_info);

  # Push
  {
    my @git_push_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'push',
      '-q',
      $wiki_rep_info->git_dir,
      'master'
    );
    # (This is bad, but --quiet option can't supress in old git)
    Gitprep::Util::run_command(@git_push_cmd)
      or croak "Can't execute git push: @git_push_cmd";
  }
}

sub rename_and_update_wiki_page {
  my ($self, $rep_info, $original_title, $title, $content, $commit_message) = @_;

  my $wiki_rep_info = $rep_info->wiki;
  my $wiki_work_rep_info = $wiki_rep_info->work;

  # Project row id
  my $project_row_id = $self->get_project_row_id($wiki_rep_info);

  # Original file name
  my $original_file_name = "$original_title.md";

  # File name
  my $file_name = "$title.md";

  # Original file abs name
  my $original_file_abs_name = $wiki_work_rep_info->work_tree($original_file_name);

  # File abs name
  my $file_abs_name = $wiki_work_rep_info->work_tree($file_name);
  my $utf8_name = encode('UTF-8', $file_abs_name);

  # Update page
  # Create file
  open my $fh, '>:encoding(UTF-8)', $utf8_name
    or die "Can't open file \"$utf8_name\": $!";

  # Write content to file
  print $fh $content;

  # Close file
  close $fh;

  # Delete original file
  my $utf8_original_name = encode('UTF-8', $original_file_abs_name);
  if (-f $utf8_original_name) {
    unlink $utf8_original_name
      or die "Can't delete file \"$utf8_original_name\": $!";
  }

  # Check file changes
  my $is_file_change;
  {
    my @git_status_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'status',
      '-s',
      $wiki_work_rep_info->work_tree
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
    $utf8_original_name
  );

  Gitprep::Util::run_command(@git_rm_cmd)
    or croak "Can't execute git rm: @git_rm_cmd";

  # Add
  my @git_add_cmd = $self->app->git->cmd(
    $wiki_work_rep_info,
    'add',
    $wiki_work_rep_info->work_tree
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

  $self->app->manager->set_remote($wiki_work_rep_info, 'origin', $wiki_rep_info);

  # Push
  {
    my @git_push_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'push',
      '-q',
      $wiki_rep_info->git_dir,
      'master'
    );
    # (This is bad, but --quiet option can't supress in old git)
    Gitprep::Util::run_command(@git_push_cmd)
      or croak "Can't execute git push: @git_push_cmd";
  }
}

sub delete_wiki_page {
  my ($self, $rep_info, $title) = @_;

  # Wiki repository
  my $wiki_rep_info = $rep_info->wiki;

  # Wiki working directory
  my $wiki_work_rep_info = $wiki_rep_info->work;

  # File name
  my $file_name = "$title.md";

  # File abs name
  my $file_abs_name = $wiki_work_rep_info->work_tree($file_name);
  my $utf8_name = encode('UTF-8', $file_abs_name);

  # Delete file
  if (-f $utf8_name) {
    unlink $utf8_name or die "Can't delete file \"$utf8_name\": $!";
  }

  # Check file changes
  my $is_file_change;
  {
    my @git_status_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'status',
      '-s',
      $wiki_work_rep_info->work_tree
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
    $utf8_name
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

  $self->app->manager->set_remote($wiki_work_rep_info, 'origin', $wiki_rep_info);

  # Push
  {
    my @git_push_cmd = $self->app->git->cmd(
      $wiki_work_rep_info,
      'push',
      '-q',
      $wiki_rep_info->git_dir,
      'master'
    );
    # (This is bad, but --quiet option can't supress in old git)
    Gitprep::Util::run_command(@git_push_cmd)
      or croak "Can't execute git push: @git_push_cmd";
  }
}

sub get_issue_count {
  my ($self, $rep_info, $opt) = @_;

  $opt ||= {};

  my $project_row_id = $self->get_project_row_id($rep_info);

  my $where = $self->app->dbi->where;
  my $clause = ['and', ':project{=}'];
  my $param = {project => $project_row_id};

  # Issue kind.
  if (exists $opt->{pull}) {
    push @$clause, $opt->{pull}? 'pull_request <> 0': 'pull_request = 0';
  }
  # Status
  if (exists $opt->{status}) {
    push @$clause, ['or', (':issue.status{=}') x scalar(@{$opt->{status}})];
    $param->{'issue.status'} = $opt->{status};
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
  my ($self, $rep_info) = @_;

  return $self->get_issue_count($rep_info, {pull => 0, status => ['open']});
}

sub get_open_pull_request_count {
  my ($self, $rep_info) = @_;

  return $self->get_issue_count($rep_info,
    {pull => 1, status => ['open', 'draft']});
}

sub api_update_issue_message {
  my ($self, $issue_message_row_id, $message, $rep_info, $rev) = @_;

  my $issue_message = $self->app->dbi->model('issue_message')->select(
    {user => ['id']}, where => {'issue_message.row_id' => $issue_message_row_id}
  )->one;

  my $json = {success => 0};
  my $session_user_id = $self->session_user_id;

  if ($session_user_id) {
    my $is_my_project = $rep_info->user eq $session_user_id;
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

      my $markdown_message = $self->markdown($message, $rep_info, rev => $rev);

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
  my ($self, $rep_info, $number, $message) = @_;
  my $issue_message_number;

  $self->app->dbi->connector->txn(sub {
    my $issue_row_id = $self->app->dbi->model('issue')->select(
      'issue.row_id',
      where => {
        'project__user.id' => $rep_info->user,
        'project.id' => $rep_info->project,
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

# Convert markdown to HTML.
# Relative urls are converted according to parameters.
# HTML tags are limited to a safe subset.
#
# Call with markdown text and rep_info as positional arguments, followed
# by named parameters.
# Parameters:
#  rev          the markdown file git revision
#  link_path    the url path component leading to a linked object (blob)
#  image_path   the url path component leading to an image (default: raw)
#  file         the markdown file path within repository
#  tree         the markdown file's directory within repository
#  site_url     Base url to convert into an absolute url (Mojo::URL).
#
# If not defined, tree is computed from file.
# Wiki links are translated only if the repository is a wiki.
sub markdown {
  my $self = shift;
  my $markdown_text = shift;
  my $rep_info = shift;
  my %params = (
    link_path => 'blob',
    image_path => 'raw',
    @_
  );
  my $rev = $params{rev};
  my $tree = $params{tree};
  my $site_url = $params{site_url};

  my %users = map {$_ => 1} @{$self->app->dbi->model('user')->select('id')->values};

  local *replace_link = sub {
    my %m = (@_);

    local *build_url = sub {
      my ($format, $urlstr) = @_;
      my $url = Mojo::URL->new($urlstr);

      # Do not replace absolute, empty or fragment-only URLs.
      unless ($url->is_abs || !defined $url->path || !@{$url->path}) {
        my $path = $url->path;

        unless ($path->leading_slash) {
          unshift @$path, @{Mojo::Path->new($tree)} if ($tree // '') ne '';
          unshift @$path, @{Mojo::Path->new($rev)} if ($rev // '') ne '';
          unshift @$path, @{Mojo::Path->new($format)} if ($format // '') ne '';
        }

        # Relative URLs are rooted by the project's repository.
        $path = $path->canonicalize();
        while (scalar(@$path) && $path->[0] eq '..') {
          shift @$path;
        }

        unshift @$path, @{$self->cntl->url_for($rep_info->url)->path};
        $path = $path->leading_slash(!$site_url);
        $url->path($path);
        $url = $url->to_abs($site_url) if $site_url;
        $urlstr = $url->to_string;
      }

      return $urlstr;
    };

    my $url = $m{url};
    my $text = $m{text};

    # Wiki link.
    #  [[Link text|Title]]
    #  [[Title]]
    if ($m{marker} eq '[[') {
      return $m{match} unless $rep_info->is_wiki;
      $text = $url if ($text // '') eq '';
      $url = $text if ($url // '') eq '';
      $url = $self->wiki_safe_title($url);
      my $r = $self->cntl->url_for($rep_info->url($url));
      $r = $r->to_abs($site_url) if $site_url;
      $r = "[$text]($r)";
      $r = "<span class=\"wiki-link-no-title\" title=\"Non-existent page\">$r</span>"
        unless $self->wiki_page_exists($rep_info, $url);
      return $r;
    }

    # Mentioned user.
    # @user.
    if ($m{marker} eq '@') {
      return $m{match} unless defined $users{$m{user}};
      my $r = $self->cntl->url_for("/$m{user}");
      $r = $r->to_abs($site_url) if $site_url;
      return "<span class=\"markdown-mentioned\">[\@$m{user}]($r)</span>";
    }

    # <img> tag.
    if ($m{marker} eq 'src') {
      $url = build_url($params{image_path}, $url);
      return "src=\"$url\"";
    }

    # <a>-like tag.
    if ($m{marker} eq 'href') {
      $url = build_url($params{link_path}, $url);
      return "href=\"$url\"";
    }

    # Markdown urls may be followed by a title.
    my $title = '';
    if ($url =~ /^(.*)(\s+'[^']*'\s*)$/ || $url =~ /^(.*)(\s+"[^"]*"\s*)$/) {
      $url = $1;
      $title = $2;
    }

    if (($text // '') eq '') {
      $text = $url;
      $text =~ s/^mailto://;      # Visual cosmetics.
    }

    # Markdown image
    #  ![text](url)
    if ($m{marker} eq '!') {
      $url = build_url($params{image_path}, $url);
      return "![$text]($url$title)";
    }

    # Markdown image link.
    #  [![text](url)](url)
    if ($m{marker} eq '[![') {
      $text = replace_link(
        marker => '!',
        text => $text,
        url => $m{url2}
      );
    }

    # Markdown link.
    #  [text](url)
    $url = build_url($params{link_path}, $url);
    return "[$text]($url$title)";
  };

  # Translate relative urls.
  if ($rep_info) {
    # Derive tree from file path if needed and possible.
    if (!defined($tree) && defined $params{file}) {
      # Get directory tree path.
      $tree = $params{file};
      $tree =~ s#(?:^|/+)[^/]*$##;
    }

    $markdown_text =~ s@(?<match>(?:
      # Markdown linking image.
      (?<marker>\[!\[?)(?<text>[^\]]*)\]\((?<url2>[^)\]]*)\)\]\((?<url>[^)]*)\)|
      # Markdown images and links.
      (?<marker>!?)\[(?<text>[^\]]*)\]\((?<url>[^)]*)\)|
      # HTML images and links.
      \b(?<marker>src|href)="(?<url>[^"]*)"|
      # Wiki link.
      #  [[Link text|Title]]
      #  [[Title]]
      (?<marker>\[\[)(?<text>[^\]\|]+?)(?:\|(?<url>[^\[\]]+?))?\]\]|
      # Mentioned user.
      (?<![a-zA-Z0-9_-])(?<marker>\@)(?<user>[a-zA-Z0-9_-]+)
    ))@replace_link(%+)@egmx;
  }

  # Convert to HTML.
  my $html_text = Text::Markdown::Hoedown::markdown($markdown_text,
    extensions => HOEDOWN_EXT_FENCED_CODE|HOEDOWN_EXT_TABLES|HOEDOWN_EXT_NO_INTRA_EMPHASIS
  );

  # Remove unsafe tags.
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
      span => [qw( title id class )],
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
      a => [qw( href title id class )],
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
      strike => [qw( class )],
      svg  => [ qw( width height viewbox xmlns ) ],
      circle => [ qw( style cx cy r stroke stroke-width fill ) ],
      path => [ qw( style d fill stroke ) ],
      rect => [ qw( style x y width height fill ) ],
      image => [ qw( x y width height href ) ]
    },
    uri_schemes => [ undef, 'http', 'https', 'mailto' ]
  );

  $html_text = $hr->process($html_text);

  return $html_text;
}

sub mentioned {
  my ($self, $message) = @_;
  my %users;

  # Scan message for @<username>s and return an array of them.

  while ($message =~ /(?:^|[^a-z0-9_\-])@([a-z0-9_\-]+)/gi) {
    $users{$1} = 1;
  }
  my @result = keys %users;
  return @result;
}

sub ssh_rep_url {
  my ($self, $rep_info) = @_;
  my $user_id = $rep_info->user;
  my $repository = $rep_info->project;

  my $config = $self->app->config;
  my $user = $config->{basic}{ssh_user} || getpwuid($>);
  my $port = $config->{basic}{ssh_port};
  my $home = $config->{basic}{'ssh_rep_url_base'} || Gitprep::Repository->home;
  my $url = "$user@" . $self->cntl->url_for->to_abs->host;

  if (!$config->{basic}{scp_url} || $port) {
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
  return Time::Moment->now_utc->epoch;
}

sub strftime {
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

  # Use viewBox parameter or try to rebuild it if not present.
  my $viewbox = delete($args{viewBox}) || $args{viewbox} ||
    $attrs->{viewBox} || $attrs->{viewbox};
  delete $args{viewbox};
  delete $attrs->{viewBox};
  delete $attrs->{viewbox};
  unless ($viewbox) {
    my $w = $attrs->{width};
    my $h = $attrs->{height};
    if (defined($w) && $w =~ /^-?\d+$/ && defined($h) && $h =~ /^-?\d+$/) {
      $viewbox = "0 0 $w $h";
    }
  }
  $attrs->{viewBox} = $viewbox if $viewbox;

  # If width and/or height are given in call, override them.
  $attrs->{width} = delete $args{width} if $args{width};
  $attrs->{height} = delete $args{height} if $args{height};

  my $class = delete $args{class};
  my $title = delete $args{title};
  my $tag = delete $args{tag};
  $attrs->{$_} = $args{$_} for (keys %args);
  $self->DOM_add_class($svg, $class) if defined $class;

  %args = ();
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

sub avatar {
  my $self = shift;
  my $size = shift;
  my $url = $self->cntl->url_for("/_avatar")->query(@_);
  my $img = $self->DOM_element('img', class => 'avatar', src => $url,
    width => $size, height => $size, alt => '');
  return $img;
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

sub notify_reason {
  my ($self, $code) = @_;

  my %reasons = (
    'C' => 'commented',
    'N' => 'authored the thread',
    'M' => 'were mentioned',
    'O' => 'own the repository',
    'S' => 'subscribed',
    'W' => 'watch the repository'
  );

  my $reason_text;
  my $subscribed = 0;

  if (!defined $code) {
    $reason_text = "didn't subscribed";
  }
  elsif ($code eq 'U') {
    $reason_text = 'unsubscribed';
  }
  else {
    $subscribed = 1;
    $reason_text = $reasons{$code};
  }

  return ($reason_text, $subscribed);
}

sub notify_subscribed {
  my ($self, $rep_info, $rev, $title, $sender_row_id, $message,
      $link, $issue_row_id, $action) = @_;
  my $user = $rep_info->user;
  my $project = $rep_info->project;

  $self->app->{mailtransport} || return;

  # Sender id, name and email address.
  my $sender = $self->app->dbi->model('user')->select(['id', 'name', 'email'],
    where => {
      row_id => $sender_row_id
    })->one;

  # Repository owner email address.
  my $ownermail = $self->app->dbi->model('user')->select('email',
    where => {
      id => $rep_info->user
    })->value;

  # Subscriptions.
  my $subscriptions = $self->app->dbi->model('subscription')->select(
    ['subscription__user.email', 'reason'],
    where => {
      issue => $issue_row_id 
    })->all;

  # Watchers.
  my $watchers = $self->app->dbi->model('watch')->select(
    ['watch__user.email'],
    where => {
      project => $self->get_project_row_id($rep_info)
    })->all;

  # Merge results.
  my %recipients = (
    $ownermail => 'O',
    (map {$_->{email} => 'W'} @$watchers),
    (map {$_->{email} => $_->{reason}} @$subscriptions)
  );

  # Filter out unsubscribed.
  %recipients = (map {$_ => $recipients{$_}}
    grep {($self->notify_reason($recipients{$_}))[1]} keys %recipients);

  # Do not send back to sender.
  delete $recipients{$sender->{email}};

  # Convert markdown message to HTML.
  $message = $self->markdown(
    $message,
    $rep_info,
    rev => $rev,
    site_url => $self->app->{site_url}
  );

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
  my $from = ($sender->{name} || $sender->{id}) . " <$conf->{from}>";
  my $to = 'undisclosed-recipients:;';
  $to = "$user/$project <$conf->{to}>" if $conf->{to};

  # Avoid multi-recipient mails as sent data can be personalized.
  for my $email (keys %recipients) {
    my $html = $self->cntl->render_to_string('/api/notify',
      rep_info => $rep_info,
      link => $link,
      message => $message,
      sender_id => $sender->{id},
      action => $action,
      reason => $recipients{$email}
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

    # Send e-mail. Avoid crashing in case of send problem.
    eval {
      Email::Sender::Simple->send(
        $top->stringify,
        {
          transport => $self->app->{mailtransport},
          from => $conf->{from},
          to => $email
        }
      );
    };
    if ($@) {
      $self->app->log->error('Cannot send e-mail: configuration error or mail server down');
      $self->app->log->error($@);
    }
  }
}

sub get_user_row_id {
  my ($self, $user_id) = @_;

  my $user_row_id = $self->app->dbi->model('user')->select('row_id', where => {id => $user_id})->value;

  return $user_row_id;
}

sub get_project_row_id {
  my ($self, $rep_info) = @_;

  my $user_row_id = $self->app->dbi->model('user')->select(
    'row_id',
    where => {id => $rep_info->user}
  )->value;
  my $project_row_id = $self->app->dbi->model('project')->select(
    'row_id',
    where => {user => $user_row_id, id => $rep_info->project}
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
  my ($self, $collaborator_id, $rep_info) = @_;

  my $user_row_id = $self->get_user_row_id($rep_info->user);
  my $project_row_id = $self->app->dbi->model('project')->select(
    where => {user => $user_row_id, id => $rep_info->project}
  )->value;
  my $collaborator_row_id = $self->get_user_row_id($collaborator_id);

  my $row = $self->app->dbi->model('collaboration')->select(
    where => {project => $project_row_id, user => $collaborator_row_id}
  )->one;

  return $row ? 1 : 0;
}

sub can_access_private_project {
  my ($self, $rep_info) = @_;

  my $session_user_row_id = $self->cntl->session('user_row_id');
  return unless defined $session_user_row_id;

  my $session_user_id = $self->app->dbi->model('user')->select(
    'id', where => {row_id => $session_user_row_id}
  )->value;

  my $is_valid =
    ($rep_info->user eq $session_user_id ||
    $self->is_collaborator($session_user_id, $rep_info))
    && $self->logged_in;

  return $is_valid;
}

sub can_write_access {
  my ($self, $session_user_id, $rep_info) = @_;

  return unless $session_user_id;

  my $can_write_access
    = length $session_user_id &&
    (
      $session_user_id eq $rep_info->user ||
        $self->is_collaborator($session_user_id, $rep_info)
    );

  return $can_write_access;
}

sub new {
  my ($class, $cntl) = @_;

  my $self = $class->SUPER::new(cntl => $cntl);

  return $self;
}

sub logged_in_as_admin {
  my $self = shift;

  # Controler
  my $c = $self->cntl;

  # Check if logged in as admin
  my $session_user_id = $self->session_user_id;

  return $self->app->manager->is_admin($session_user_id) && $self->logged_in($session_user_id);
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

sub logged_in {
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

  my $logged_in;
  if (defined $user_id) {
    $logged_in = $user_id eq $session_user_id && $password eq $correct_password;
  }
  else {
    $logged_in = $password eq $correct_password
  }

  return $logged_in;
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
