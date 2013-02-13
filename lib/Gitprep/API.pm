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

1;

