#!/bin/sh
perl cpanm -n -l extlib Module::CoreList
perl -Iextlib/lib/perl5 cpanm -n -L extlib --installdeps .
