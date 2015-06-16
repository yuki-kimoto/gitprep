#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/mojo/lib";
use lib "$FindBin::Bin/extlib/lib/perl5";

$ENV{MOJO_MODE} = 'production';
require "$FindBin::Bin/script/gitprep";
