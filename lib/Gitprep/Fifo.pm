package Gitprep::Fifo;
use Mojo::Base -base;
use parent 'Mojo::EventEmitter';

use strict;

# General use data fifo with events support.

has 'low' => sub {1};
has 'high' => sub {4};

sub new {
  my ($class, $high) = @_;
  my $self = bless {
    items => []
  }, $class;
  $self->high($high)->low($high / 4) if defined $high;
  return $self;
}

sub push {
  my ($self, $data) = @_;
  my $items = $self->{items};
  push @$items, $data;
  $self->emit(ready => scalar(@$items));
  $self->emit(high => scalar(@$items)) if @$items >= $self->high;
  return $self;
}

sub pop {
  my ($self, $maxsize) = @_;
  my $items = $self->{items};
  my $data = shift @$items;
  if ($maxsize && defined $data) {
    my $len = length $data;
    if ($len > $maxsize) {
      ($data, my $pushback) = unpack("a$len a*", $data);
      unshift @$items, $pushback;
      return $data;
    }
  }
  $self->emit(low => scalar(@$items)) if @$items <= $self->low;
  $self->emit('empty') unless @$items;
  return $data;
}

sub empty {
  my $self = shift;
  return !@{$self->{items}};
}

sub clear {
  my $self = shift;
  $self->items = [];
  $self->emit(low => 0);
  $self->emit('empty');
  return $self;
}

1;
