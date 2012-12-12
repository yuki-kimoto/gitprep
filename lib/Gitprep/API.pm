package Gitprep::API;
use Mojo::Base -base;

use Carp ();
use File::Basename ();

sub croak { Carp::croak(@_) }
sub dirname { File::Basename::dirname(@_) }

has 'cntl';

sub new {
  my ($class, $cntl) = @_;

  my $self = $class->SUPER::new(cntl => $cntl);
  
  return $self;
}

sub root_ns {
  my ($self, $root) = @_;

  $root =~ s/^\///;
  
  return $root;
}

sub parse_id_path {
  my ($self, $project, $id_path) = @_;
  
  my $c = $self->cntl;
  
  # Git
  my $git = $c->app->git;
  
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

sub trees {
  my ($self, $rep, $tid, $ref, $dir) = @_;
  
  my $c = $self->cntl;
  
  my $git = $c->app->git;
  
  # Get tree (command "git ls-tree")
  my @entries = ();
  my $show_sizes = 0;
  open my $fh, '-|', $git->cmd($rep), 'ls-tree', '-z',
      ($show_sizes ? '-l' : ()), $tid
    or $self->croak('Open git-ls-tree failed');
  {
    local $/ = "\0";
    @entries = map { chomp; $git->dec($_) } <$fh>;
  }
  close $fh
    or $self->croak(404, "Reading tree failed");

  # Parse tree
  my $trees;
  for my $line (@entries) {
    my $tree = $git->parse_ls_tree_line($line, -z => 1, -l => $show_sizes);
    $tree->{mode_str} = $git->_mode_str($tree->{mode});
    
    # Commit log
    my $name = defined $dir ? "$dir/$tree->{name}" : $tree->{name};
    my $commit_log = $git->latest_commit_log($rep, $ref, $name);
    $tree = {%$tree, %$commit_log};
    
    push @$trees, $tree;
  }
  $trees = [sort {$b->{type} cmp $a->{type} || $a->{name} cmp $b->{name}} @$trees];
  
  return $trees;
}

1;

