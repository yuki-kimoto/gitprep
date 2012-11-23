package Gitweblite::Main;
use Mojo::Base 'Mojolicious::Controller';
use File::Basename 'dirname';
use Carp 'croak';

sub blob {
  my $self = shift;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id_file = $self->param('id_file');

  # Id and file
  my ($id, $file) = $self->_parse_id_path($project, $id_file);

  # Git
  my $git = $self->app->git;

  # Blob content
  my $bid = $git->id_by_path($project, $id, $file, 'blob')
    or croak 'Cannot find file';
  my @cmd = ($git->cmd($project), 'cat-file', 'blob', $bid);
  open my $fh, '-|', @cmd
    or croak qq/Couldn't cat "$file", "$bid"/;
  
  # Blob plain
  if ($self->stash('plain')) {
    # Content type
    my $type = $git->blob_contenttype($fh, $file);

    # Convert text/* content type to text/plain
    if ($self->config('prevent_xss') &&
      ($type =~ m#^text/[a-z]+\b(.*)$# ||
      ($type =~ m#^[a-z]+/[a-z]\+xml\b(.*)$# && -T $fh)))
    {
      my $rest = $1;
      $rest = defined $rest ? $rest : '';
      $type = "text/plain$rest";
    }

    # File name
    my $file_name = $id;
    if (defined $file) { $file_name = $file }
    elsif ($type =~ m/^text\//) { $file_name .= '.txt' }
    
    # Content
    my $content = do { local $/; <$fh> };
    my $sandbox = $self->config('prevent_xss') &&
      $type !~ m#^(?:text/[a-z]+|image/(?:gif|png|jpeg))(?:[ ;]|$)#;
    my $content_disposition = $sandbox ? 'attachment' : 'inline';
    $content_disposition .= "; filename=$file_name";
    
    # Render
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type($type);
    $self->render_data($content);
  }
  
  # Blob
  else {
    # MIME type
    my $mimetype = $git->blob_mimetype($fh, $file);
    
    # Redirect to blob-plain if no display MIME type
    if ($mimetype !~ m#^(?:text/|image/(?:gif|png|jpeg)$)# && -B $fh) {
      close $fh;
      my $url = $self->url_for('blob_plain',
        project => $project_ns, id_file => "$id/$file");
      
      return $self->redirect_to($url);
    }
    
    # Commit
    my $commit = $git->parse_commit($project, $id);

    # Parse line
    my @lines;
    while (my $line = $git->dec(scalar <$fh>)) {
      chomp $line;
      $line = $git->_tab_to_space($line);
      push @lines, $line;
    }
    
    # Render
    $self->render(
      home => $home,
      home_ns => $home_ns,
      project => $project,
      project_ns => $project_ns,
      commit => $commit,
      id => $id,
      file => $file,
      bid => $bid,
      lines => \@lines,
      mimetype => $mimetype
    );
  }
}

sub blobdiff {
  my $self = shift;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $diff = $self->param('diff');
  my $file = $self->param('file');
  my $from_file = $self->param('from-file');
  $from_file = $file unless defined $from_file;
  my $plain = $self->param('plain');
  my $from_id;
  my $id;
  if ($diff =~ /\.\./) { ($from_id, $id) = $diff =~ /(.+)\.\.(.+)/ }
  else { $id = $diff }
  
  # Git
  my $git = $self->app->git;

  # Get blob diff (command "git diff")
  open my $fh, '-|', $git->cmd($project), 'diff', '-r', '-M', '-p',
      $from_id, $id, '--', $from_file, $file
    or croak "Open git-diff-tree failed";
  
  # Blob diff plain
  if ($plain) {
    # Content
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Render
    my $content_disposition .= "inline; filename=$file";
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type("text/plain; charset=" . $git->encoding);
    $self->render(data => $content);
  }
  
  # Blob diff
  else {
    # Lines
    my @lines = map { $git->dec($_) } <$fh>;
    close $fh;
    my $lines = $self->_parse_blobdiff_lines(\@lines);
    
    # Commit
    my $commit = $git->parse_commit($project, $id);
    
    # Render
    $self->render(
      '/blobdiff',
      home => $home,
      home_ns => $home_ns,
      project => $project,
      project_ns => $project_ns,
      id => $id,
      from_id => $from_id,
      file => $file,
      from_file => $from_file,
      commit => $commit,
      lines => $lines
    );
  }
}

sub commit {
  my $self = shift;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  
  # Git
  my $git = $self->app->git;

  # Commit
  my $commit = $git->parse_commit($project, $id);
  my $committer_date
    = $git->parse_date($commit->{committer_epoch}, $commit->{committer_tz});
  my $author_date
    = $git->parse_date($commit->{author_epoch}, $commit->{author_tz});
  $commit->{author_date} = $git->timestamp($author_date);
  $commit->{committer_date} = $git->timestamp($committer_date);
  
  # References
  my $refs = $git->references($project);
  
  # Diff tree
  my $parent = $commit->{parent};
  my $parents = $commit->{parents};
  my $difftrees = $git->difftree($project, $commit->{id}, $parent, $parents);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    id => $id,
    commit => $commit,
    refs => $refs,
    difftrees => $difftrees,
  );
}

sub commitdiff {
  my $self = shift;
  
  # Paramters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $diff = $self->param('diff');
  my ($from_id, $id) = $diff =~ /(.+)\.\.(.+)/;
  $id = $diff unless defined $id;
  
  # Git
  my $git = $self->app->git;
  
  # Commit
  my $commit = $git->parse_commit($project, $id)
    or croak 'Unknown commit object';
  my $author_date
    = $git->parse_date($commit->{author_epoch}, $commit->{author_tz});
  my $committer_date
    = $git->parse_date($commit->{committer_epoch}, $commit->{committer_tz});
  $commit->{author_date} = $git->timestamp($author_date);
  $commit->{committer_date} = $git->timestamp($committer_date);
  $from_id = $commit->{parent} unless defined $from_id;
  
  # Plain text
  if ($self->param('plain')) {
    # Get blob diffs (command "git diff-tree")
    my @cmd = ($git->cmd($project), 'diff-tree', '-r', '-M',
        '-p', $from_id, $id, '--');
    open my $fh, '-|', @cmd
      or croak 'Open git-diff-tree failed';

    # Content
    my $content = do { local $/; <$fh> };
    my $content_disposition .= "inline; filename=$id";
    
    # Render
    $self->res->headers->content_disposition($content_disposition);
    $self->res->headers->content_type("text/plain;charset=" . $git->encoding);
    $self->render_data($content);
  }
  
  # HTML
  else {
    
    # Diff tree
    my $difftrees = $git->difftree($project,
      $id, $commit->{parent}, $commit->{parents});
    
    # Get blob diffs (command "git diff-tree")
    my @cmd = ($git->cmd($project), 'diff-tree', '-r', '-M',
      '--no-commit-id', '--patch-with-raw', $from_id, $id, '--');
    open my $fh, '-|', @cmd
      or croak 'Open git-diff-tree failed';

    # Parse output
    my @blobdiffs;
    while (my $line = $git->dec(scalar <$fh>)) {
      
      # Parse line
      chomp $line;
      my $diffinfo = $git->parse_difftree_raw_line($line);
      my $from_file = $diffinfo->{from_file};
      my $file = $diffinfo->{to_file};
      
      # Get blobdiff (command "git diff-tree")
      my @cmd = ($git->cmd($project), 'diff-tree', '-r', '-M', '-p',
        $from_id, $id, '--', (defined $from_file ? $from_file : ()), $file);
      open my $fh_blobdiff, '-|', @cmd
        or croak 'Open git-diff-tree failed';
      my @lines = map { $git->dec($_) } <$fh>;
      close $fh_blobdiff;
      my $blobdiff = {
        file => $file,
        from_file => $from_file,
        lines => $self->_parse_blobdiff_lines(\@lines)
      };
      
      # Status
      for my $difftree (@$difftrees) {
        if ($difftree->{to_file} eq $file) {
          $blobdiff->{status} = $difftree->{status};
          last;
        }
      }
      
      push @blobdiffs, $blobdiff;
    }

    # References
    my $refs = $git->references($project);
    
    # Render
    $self->render(
      'commitdiff',
      home => $home,
      home_ns => $home_ns,
      project => $project,
      project_ns => $project_ns,
      from_id => $from_id,
      id => $id,
      commit => $commit,
      difftrees => $difftrees,
      blobdiffs => \@blobdiffs,
      refs => $refs
    );
  }
}

sub home {
  my $self = shift;

  # Search git repositories
  my $dirs = $self->app->config('search_dirs');
  my $max_depth = $self->app->config('search_max_depth');
  my $projects = $self->app->git->search_projects(
    dirs => $dirs,
    max_depth => $max_depth
  );
  
  # Home
  my $homes = {};
  $homes->{$_->{home}} = 1 for @$projects;
  
  $self->render(homes => [keys %$homes]);
}


sub heads {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $heads  = $git->heads($project);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    heads => $heads,
  );
}

sub log {
  my ($self, %opt) = @_;

  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  my $page = $self->param('page');
  $page = 0 if !defined $page;
  my $short = $self->param('short');
  
  # Git
  my $git = $self->app->git;
  
  # Commit
  my $commit = $git->parse_commit($project, $id);
  
  # Commits
  my $page_count = $short ? 50 : 20;
  my $commits = $git->parse_commits(
    $project, $commit->{id},$page_count, $page_count * $page);
  for my $commit (@$commits) {
    my $author_date
      = $git->parse_date($commit->{author_epoch}, $commit->{author_tz});
    $commit->{author_date} = $git->timestamp($author_date);
  }
  
  # References
  my $refs = $git->references($project);

  # Render
  $self->stash->{action} = 'shortlog' if $short;
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    id => $id,
    commits => $commits,
    refs => $refs,
    page => $page,
    page_count => $page_count
  );
};

sub projects {
  my $self = shift;
  
  # Parameters
  my $home_ns = $self->param('home');
  my $home = "/$home_ns";

  # Git
  my $git = $self->app->git;
  
  # Fill project information
  my $projects = $git->projects($home);
  $projects = $git->fill_projects($home, $projects);
  
  # Fill owner and HEAD commit id
  for my $project (@$projects) {
    my $pname = "$home/$project->{path}";
    $project->{path_abs_ns} = "$home_ns/$project->{path}";
    $project->{owner} = $git->project_owner($pname);
    my $head_commit = $git->parse_commit($pname, 'HEAD');
    $project->{head_id} = $head_commit->{id}
  }
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    projects => $projects
  );
}

sub snapshot {
  my $self = shift;

  # Parameter
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  
  # Git
  my $git = $self->app->git;

  # Object type
  my $type = $git->object_type($project, "$id^{}");
  if (!$type) { croak 404, 'Object does not exist' }
  elsif ($type eq 'blob') { croak 400, 'Object is not a tree-ish' }
  
  my ($name, $prefix) = $git->snapshot_name($project, $id);
  my $file = "$name.tar.gz";
  my $cmd = $self->_quote_command(
    $git->cmd($project), 'archive', "--format=tar", "--prefix=$prefix/", $id
  );
  $cmd .= ' | ' . $self->_quote_command('gzip', '-n');

  $file =~ s/(["\\])/\\$1/g;

  open my $fh, '-|', $cmd
    or croak 'Execute git-archive failed';
  
  # Write chunk
  $self->res->headers->content_type('application/x-tar');
  $self->res->headers->content_disposition(qq/attachment; filename="$file"/);
  my $cb;
  $cb = sub {
    my $c = shift;
    my $size = 500 * 1024;
    my $length = sysread($fh, my $buffer, $size);
    unless (defined $length) {
      close $fh;
      undef $cb;
      return;
    }
    $c->write_chunk($buffer, $cb);
  };
  $self->$cb;
}

sub summary {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  
  # Git
  my $git = $self->app->git;
  
  # HEAd commit
  my $project_description = $git->project_description($project);
  my $project_owner = $git->project_owner($project);
  my $head_commit = $git->parse_commit($project, 'HEAD');
  my $committer_date
    = $git->parse_date($head_commit->{committer_epoch}, $head_commit->{committer_tz});
  my $last_change = $git->timestamp($committer_date);
  my $head_id = $head_commit->{id};
  my $urls = $git->project_urls($project);
  
  # Commits
  my $commit_count = 20;
  my $commits = $head_id ? $git->parse_commits($project, $head_id, $commit_count) : ();

  # References
  my $refs = $git->references($project);
  
  # Tags
  my $tag_count = 20;
  my $tags  = $git->tags($project, $tag_count - 1);

  # Heads
  my $head_count = 20;
  my $heads = $git->heads($project, $head_count - 1);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    project_description => $project_description,
    project_owner => $project_owner,
    last_change => $last_change,
    urls => $urls,
    commits => $commits,
    tags => $tags,
    head_id => $head_id,
    heads => $heads,
    refs => $refs,
    commit_count => $commit_count,
    tag_count => $tag_count,
    head_count => $head_count
  );
}

sub tag {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id = $self->param('id');
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $tag  = $git->parse_tag($project, $id);
  my $author_date
    = $git->parse_date($tag->{author_epoch}, $tag->{author_tz});
  $tag->{author_date} = $git->timestamp($author_date);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    tag => $tag,
  );
}

sub tags {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  
  # Git
  my $git = $self->app->git;
  
  # Ref names
  my $tags  = $git->tags($project);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    tags => $tags,
  );
}

sub tree {
  my $self = shift;
  
  # Parameters
  my $project_ns = $self->param('project');
  my $project = "/$project_ns";
  my $home_ns = dirname $project_ns;
  my $home = "/$home_ns";
  my $id_dir = $self->param('id_dir');

  # Id and directory
  my ($id, $dir) = $self->_parse_id_path($project, $id_dir);

  # Git
  my $git = $self->app->git;
  
  # Tree id
  my $tid;
  my $commit = $git->parse_commit($project, $id);
  unless (defined $tid) {
    if (defined $dir && $dir ne '') {
      $tid = $git->id_by_path($project, $id, $dir, 'tree');
    }
    else { $tid = $commit->{tree} }
  }
  $self->render_not_found unless defined $tid;

  # Get tree (command "git ls-tree")
  my @entries = ();
  my $show_sizes = 0;
  open my $fh, '-|', $git->cmd($project), 'ls-tree', '-z',
      ($show_sizes ? '-l' : ()), $tid
    or croak 'Open git-ls-tree failed';
  local $/ = "\0";
  @entries = map { chomp; $git->dec($_) } <$fh>;
  close $fh
    or croak 404, "Reading tree failed";
  
  # Parse tree
  my @trees;
  for my $line (@entries) {
    my $tree = $git->parse_ls_tree_line($line, -z => 1, -l => $show_sizes);
    $tree->{mode_str} = $git->_mode_str($tree->{mode});
    push @trees, $tree;
  }
  
  # References
  my $refs = $git->references($project);
  
  # Render
  $self->render(
    home => $home,
    home_ns => $home_ns,
    project => $project,
    project_ns => $project_ns,
    dir => $dir,
    id => $id,
    tid => $tid,
    commit => $commit,
    trees => \@trees,
    refs => $refs
  );
}

sub _parse_blobdiff_lines {
  my ($self, $lines_raw) = @_;
  
  # Git
  my $git = $self->app->git;
  
  # Parse
  my @lines;
  for my $line (@$lines_raw) {
    $line = $git->dec($line);
    chomp $line;
    my $class;
    
    if ($line =~ /^diff \-\-git /) { $class = 'diff header' }
    elsif ($line =~ /^index /) { $class = 'diff extended_header' }
    elsif ($line =~ /^\+/) { $class = 'diff to_file' }
    elsif ($line =~ /^\-/) { $class = 'diff from_file' }
    elsif ($line =~ /^\@\@/) { $class = 'diff chunk_header' }
    elsif ($line =~ /^Binary files/) { $class = 'diff binary_file' }
    else { $class = 'diff' }
    push @lines, {value => $line, class => $class};
  }
  
  return \@lines;
}

sub _parse_id_path {
  my ($self, $project, $id_path) = @_;
  
  # Git
  my $git = $self->app->git;
  
  # Parse id and path
  my $refs = $git->references($project);
  my $id;
  my $path;
  for my $rs (values %$refs) {
    for my $ref (@$rs) {
      $ref =~ s#^heads/##;
      $ref =~ s#^tags/##;
      if ($id_path =~ s#^\Q$ref(/|$)##) {
        $id = $ref;
        $path = $id_path;
        last;
      }      
    }
  }
  unless (defined $id) {
    if ($id_path =~ s#(^[^/]+)(/|$)##) {
      $id = $1;
      $path = $id_path;
    }
  }
  
  return ($id, $path);
}

sub _quote_command {
  my $self = shift;
  return join(' ',
    map { my $a = $_; $a =~ s/(['!])/'\\$1'/g; "'$a'" } @_ );
}

1;
