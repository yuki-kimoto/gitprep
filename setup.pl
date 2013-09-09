#!/usr/bin/env perl

system "$^X cpanm -n -l extlib Module::CoreList";
system "$^X -Iextlib/lib/perl5 cpanm -n -L extlib --installdeps .";
