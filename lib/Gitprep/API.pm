package Gitprep::API;
use Mojo::Base -base;

use Digest::MD5 'md5_hex';

has 'cntl';

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
  my ($self, $user, $password) = @_;
  
  my $row
    = $self->app->dbi->model('user')->select(['password', 'salt'], id => $user)->one;
  
  return unless $row;
  
  my $is_valid = $self->check_password(
    $password,
    $row->{salt},
    $row->{password}
  );
  
  return $is_valid;
}

sub git {
  my $self = shift;

  my $git = $self->app->git->clone;
  
  my $user = $self->cntl->param('user');
  my $project = $self->cntl->param('project');
  
  if (defined $user && defined $project){
    # Project encoding
    my $encoding = $self->app->dbi->model('project')->select(
      'encoding',
      id => [$user, $project]
    )->value;
    $git->encoding($encoding) if length $encoding;
  }

  return $git;
}

sub is_collaborator {
  my ($self, $user, $project, $session_user) = @_;

  $session_user = $self->cntl->session('user') unless defined $session_user;
  
  my $row = $self->app->dbi->model('collaboration')->select(
    id => [$user, $project, $session_user]
  )->one;
  
  return $row ? 1 : 0;
}

sub can_access_private_project {
  my ($self, $user, $project) = @_;

  my $session_user = $self->cntl->session('user');
  return unless $session_user;
  
  my $is_valid =
    ($user eq $session_user || $self->is_collaborator($user, $project))
    && $self->logined;
  
  return $is_valid;
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
  my $user = $c->session('user');
  
  return $self->app->manager->is_admin($user) && $self->logined($user);
}

sub logined {
  my ($self, $user) = @_;
  
  my $c = $self->cntl;
  
  my $dbi = $c->app->dbi;
  
  my $current_user = $c->session('user');
  my $password = $c->session('password');
  return unless defined $password;
  
  my $correct_password
    = $dbi->model('user')->select('password', id => $current_user)->value;
  return unless defined $correct_password;
  
  my $logined;
  
  if (defined $user) {
    $logined = $user eq $current_user && $password eq $correct_password;
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

