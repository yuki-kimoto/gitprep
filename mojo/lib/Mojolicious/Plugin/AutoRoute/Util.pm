package Mojolicious::Plugin::AutoRoute::Util;

use strict;
use warnings;
use base 'Exporter';

our @EXPORT_OK = ('template');

sub template {
  my $template = shift;
  
  return sub {
    my $self = shift;
    $self->render($template, 'mojo.maybe' => 1);
    $self->stash('mojo.finished') ? undef : $self->render_not_found;
  };
}

1;
