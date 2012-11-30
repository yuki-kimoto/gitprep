package D;

use strict;
use warnings;

use base 'Exporter';

use Data::Dumper 'Dumper';

our @EXPORT = ('d');

sub d {
    my $data = shift;
    my $dump = Dumper $data;
    print STDERR $dump;
}

1;