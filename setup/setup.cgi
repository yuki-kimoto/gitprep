#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../mojo/lib";
BEGIN { $ENV{MOJO_MODE} = 'production' }
use Mojolicious::Lite;
use Carp 'croak';

any '/' => 'index';

app->start;

