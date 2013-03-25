package Gitprep::API;
use Mojo::Base -base;

use Carp ();
use File::Basename ();
use Mojo::JSON;
use Encode qw/encode decode/;

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

sub json {
  my ($self, $value) = @_;
  
  if (ref $value) {
    return decode('UTF-8', Mojo::JSON->new->encode($value));
  }
  else {
    return Mojo::JSON->new->decode(encode('UTF-8', $value));
  }
}

sub users {
  my $self = shift;
 
  my $users = $self->cntl->app->dbi->model('user')->select(
    ['id', 'config'],
    append => 'order by id'
  )->filter(config => 'json')->all;

  @$users = grep { ! $_->{config}{admin} } @$users;
  
  return $users;
}

sub logined {
  my $self = shift;
  
  my $c = $self->cntl;
  
  my $dbi = $c->app->dbi;
  
  my $id = $c->session('user_id');
  my $password = $c->session('user_password');
  return unless defined $password;
  
  my $row = $dbi->model('user')->select('config', id => $id)->one;
  return unless $row;
  my $config = $self->json($row->{config});
  
  return $password eq $config->{password};
}

sub params {
  my $self = shift;
  
  my $c = $self->cntl;
  
  my %params = map { $_ => $c->param($_) } $c->param;
  
  return \%params;
}

sub default_branch {
  my ($self, $user, $project) = @_;
  
  my $c = $self->cntl;
  my $dbi = $c->app->dbi;
  my $row = $dbi->model('project')
    ->select('config', id => [$user, $project])->one;
  return unless $row;
  
  my $config = $self->json($row->{config});

  
  return $config->{default_branch};
}

sub delete_project {
  my ($self, $user, $project) = @_;
  
  my $c = $self->cntl;
  my $dbi = $c->app->dbi;
  $dbi->model('project')->delete(id => [$user, $project]);
}

sub exists_project {
  my ($self, $user, $project) = @_;

  my $c = $self->cntl;
  my $dbi = $c->app->dbi;
  my $row = $dbi->model('project')->select(id => [$user, $project])->one;
  
  return $row ? 1 : 0;
}

sub rename_project {
  my ($self, $user, $project, $renamed_project) = @_;
  
  my $c = $self->cntl;
  my $dbi = $c->app->dbi;
  
  croak "Invalid parameters"
    unless defined $user && defined $project && defined $renamed_project;
  
  $dbi->model('project')->update({name => $renamed_project}, id => [$user, $project]);
}

1;

