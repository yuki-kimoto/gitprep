package Gitprep::RPC;

use Mojo::JSON qw(decode_json encode_json);

# JSON-based RPC.
# Used in git hook scripts to access app objects in gitprep git shell.

sub new () {
  my ($class, $send, $base) = @_;
  my $self = {
    input_buffer => '',
    send => $send // sub {print shift},
    base => $base
  };
  bless $self, $class;
  return $self;
}

sub feed {
  my ($self, $input) = @_;

  # Append data to current input.
  $self->{input_buffer} .= $input;
}

sub line {
  my ($self, $peek) = @_;

  # Get a full line from input buffer.
  $self->{input_buffer} =~ /^(.*?)\n(.*)$/s or return undef;
  $self->{input_buffer} = $2 unless $peek;
  return $1;
}

# Server-side API.
sub serve {
  my ($self) = @_;

  # Perform a request.
  # They are transmitted has a json structure with the following fields:
  # - code: Perl-syntax expression based at the RPC server base and using only
  #         scalar/reference variables.
  # - args: hash containing all variables referenced by code.
  # The expression result is returned.
  my $input = $self->line;
  return 0 unless defined $input;
  my $request = decode_json($input);

  my $_base = $self->{base};
  my $_code = $request->{code};
  $_code = $_code? '$_base->' . $_code: 'undef';
  my $_args = $request->{args} // {};
  my @defs = (map 'my $' . $_ . '=$_args->{' . $_ . '};', keys(%$_args));
  $_code = join('', @defs) . "return $_code;";
  my $_reply;
  {
    $_reply = {reply => eval $_code};
    $_reply = {error => $@} if $@;
  }
  $_reply = encode_json($_reply);
  $_reply =~ s/[\r\n]//gs;
  $self->{send}("$_reply\n");
  return 1;
}


# Client-side API.
sub request {
  my $self = shift;
  my $code = shift;

  # Send a request.
  my $request = encode_json({code => $code, args => {@_}});
  $request =~ s/[\r\n]//gs;
  $self->{send}("$request\n");
}

sub result {
  my ($self) = @_;

  # Decode and return a reply if available.
  my $input = $self->line;
  return undef unless defined $input;
  $input = decode_json($input);
  return ($input->{reply}, $input->{error}, 1);
}


1;
