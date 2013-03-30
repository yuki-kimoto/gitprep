#!/usr/bin/env perl
use Mojo::Base -strict;

use File::Basename qw/basename dirname/;
use File::Spec::Functions qw/catdir splitdir/;

# Source directory has precedence
my $script_name = basename __FILE__;
my $base_dir_name = $script_name =~ s/\.cgi$//;
my @base_dir = (splitdir(dirname __FILE__), $base_dir_name);
my $mojolegacy = join('/', @base_dir, 'mojolegacy');
my $lib = join('/', @base_dir, 'lib');
my $extlib = join('/', @base_dir, 'extlib');
push(@INC, $mojolegacy, $extlib, $lib);

my $lib = join('/', @base, 'lib');

# Check if Mojolicious is installed;
die <<EOF unless eval 'use Mojolicious::Commands; 1';
It looks like you don't have the Mojolicious framework installed.
Please visit http://mojolicio.us for detailed installation instructions.

EOF

# Start commands
Mojolicious::Commands->start_app('Gitprep');
