#!/bin/sh
CUR_DIR_ABS=$(cd $(dirname $0); pwd)
export PERL_CPANM_HOME=$CUR_DIR_ABS/setup
perl cpanm -n -l extlib Module::CoreList
perl -Iextlib/lib/perl5 cpanm -n -L extlib --installdeps .
