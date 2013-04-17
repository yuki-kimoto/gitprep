package Gitprep::API;
use Mojo::Base -base;

use Carp ();
use File::Basename ();
use Encode qw/encode decode/;
use Digest::MD5 'md5_hex';

sub croak { Carp::croak(@_) }
sub dirname { File::Basename::dirname(@_) }

has 'cntl';

sub app { shift->cntl->app }

sub admin_user {
  my $self = shift;
  
  # Admin user
  my $admin_user = $self->app->dbi->model('user')
    ->select('id', where => {admin => 1})->value;
  
  return $admin_user;
}

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

sub exists_admin {
  my $self = shift;
 
  my $row = $self->app->dbi->model('user')
    ->select(where => {admin => 1})->one;

  return $row ? 1 : 0;;
}

sub root_ns {
  my ($self, $root) = @_;

  $root =~ s/^\///;
  
  return $root;
}

sub is_admin {
  my ($self, $user) = @_;
  
  # Check admin
  my $is_admin = $self->app->dbi->model('user')
    ->select('admin', id => $user)->value;
  
  return $is_admin;
}

sub logined_admin {
  my $self = shift;

  # Controler
  my $c = $self->cntl;
  
  # Check logined as admin
  my $user = $c->session('user');
  
  return $self->is_admin($user) && $self->logined;
}

sub logined {
  my $self = shift;
  
  my $c = $self->cntl;
  
  my $dbi = $c->app->dbi;
  
  my $user = $c->session('user');
  my $password = $c->session('password');
  return unless defined $password;
  
  my $correct_password
    = $dbi->model('user')->select('password', id => $user)->value;
  return unless defined $correct_password;
  
  return $password eq $correct_password;
}

sub users {
  my $self = shift;
 
  my $users = $self->app->dbi->model('user')->select(
    'id',
    where => [':admin{<>}',{admin => 1}],
    append => 'order by id'
  )->all;
  
  return $users;
}

sub params {
  my $self = shift;
  
  my $c = $self->cntl;
  
  my %params = map { $_ => $c->param($_) } $c->param;
  
  return \%params;
}

sub default_branch {
  my ($self, $user, $project) = @_;
  
  my $default_branch = $self->app->dbi->model('project')
    ->select('default_branch', id => [$user, $project])
    ->value;
  
  return $default_branch;
}

1;

