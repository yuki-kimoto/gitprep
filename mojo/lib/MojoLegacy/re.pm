package MojoLegacy::re;
use base 'Exporter';

our @EXPORT_OK   = ('regexp_pattern');

sub regexp_pattern {
  my $ref = shift;
  if (ref $ref eq 'Regexp') {
    return ($ref =~ qr{\(\?([^:]+):(.+)\)}) if wantarray;
    return ($ref =~ qr{(.+)})[0];
  }
  return () if wantarray;
  return 0;
}

=head1 NAME

MojoLegacy::re - emulation for re::regexp_pattern for mojo-legacy

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 Exportable Functions

=head2 regexp_pattern($ref)

If the argument is a compiled regular expression as returned by C<qr//>,
then this function returns the pattern.

In list context it returns a two element list, the first element
containing the pattern and the second containing the modifiers used when
the pattern was compiled.

  my ($pat, $mods) = regexp_pattern($ref);

In scalar context it returns the same as perl would when strigifying a raw
C<qr//> with the same pattern inside.  If the argument is not a compiled
reference then this routine returns false but defined in scalar context,
and the empty list in list context. Thus the following

    if (regexp_pattern($ref) eq '(?i-xsm:foo)')

will be warning free regardless of what $ref actually is.

=cut
