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
  
  return md5_hex(md5_hex "$salt$password") eq $password_encrypted;
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
  
  my %params = map { $_ => $c->param($_) } $c->param;
  
  return \%params;
}

1;

