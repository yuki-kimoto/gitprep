package Mojolicious::Plugin::JSONConfigLoose;
use Mojo::Base 'Mojolicious::Plugin::JSONConfig';

sub load {
  my ($self, $file, $conf, $app) = @_;
  $app->log->debug(qq/Reading config file "$file"./);

  # Slurp UTF-8 file
  open my $handle, "<:encoding(UTF-8)", $file
    or die qq/Couldn't open config file "$file": $!/;
  my $content;
  while (my $line = <$handle>) {
    if ($line =~ m#^\s*//#) {
      $content .= "\n";
      next;
    }
    else { $content .= $line }
  }

  # Process
  return $self->parse($content, $file, $conf, $app);
}

1;
