use FindBin;
use lib "$FindBin::Bin/../extlib/lib/perl5";
use 5.008007;

=pod

run mvt.pl to create this module version test(t/module.t).

  perl mvt.pl

=cut


# Created by Test::ModuleVersion 0.15
use Test::More;
use strict;
use warnings;
use ExtUtils::Installed;

sub main {
  my $command = shift;
  my @options = @_;
  
  die qq/command "$command" is unkonwn command/
    if defined $command && $command ne 'list';
  
  my $list_failed;
  my $lwp = 'auto';
  for my $option (@options) {
    if ($option eq '--fail') { $list_failed = 1 }
    elsif ($option eq '--lwp') { $lwp = 'use' }
    elsif ($option eq '--no-lwp') { $lwp = 'no' }
    else { die qq/list $option is unknown option/ }
  }
  
  if (defined $command) {
    my $builder = Test::More->builder;
    open my $out_fh, '>', undef;
    $builder->output($out_fh);
    $builder->failure_output($out_fh);
    $builder->todo_output($out_fh);
  }

  my $modules = [];
  my $failed = [];
  my $require_ok;
  my $version_ok;
  my $version;
  
  plan tests => 0;

  # Print module URLs
  if (defined $command) {
    my $distnames = {}

    ;
    my $privates = {}

    ;
    my $tm = Test::ModuleVersion->new;
    my @ms = $command eq 'list' && $list_failed ? @$failed
      : $command eq 'list' ? @$modules
      : [];
    for my $m (@ms) {
      my ($module, $version) = @$m;
      my $mu = Test::ModuleVersion::ModuleURL->new;
      $mu->distnames($distnames);
      $mu->privates($privates);
      $mu->lwp($lwp);
      my $url = $mu->get($module, $version);
      if (defined $url) { print "$url\n" }
      else { print STDERR $mu->error . "\n" }
    }  
  }
}

use 5.008007;
package Test::ModuleVersion;
our $VERSION = '0.15';

package
  Test::ModuleVersion::Object::Simple;

our $VERSION = '3.0626';

use strict;
use warnings;
no warnings 'redefine';

use Carp ();

sub import {
    my ($class, @methods) = @_;
    
    # Caller
    my $caller = caller;
    
    # Base
    if ((my $flag = $methods[0] || '') eq '-base') {

        # Can haz?
        no strict 'refs';
        no warnings 'redefine';
        *{"${caller}::has"} = sub { attr($caller, @_) };
        
        # Inheritance
        if (my $module = $methods[1]) {
            $module =~ s/::|'/\//g;
            require "$module.pm" unless $module->can('new');
            push @{"${caller}::ISA"}, $module;
        }
        else {
            push @{"${caller}::ISA"}, $class;
        }

        # strict!
        strict->import;
        warnings->import;

        # Modern!
        feature->import(':5.10') if $] >= 5.010;        
    }
    # Method export
    else {
        
        # Exports
        my %exports = map { $_ => 1 } qw/new attr class_attr dual_attr/;
        
        # Export methods
        foreach my $method (@methods) {
            
            # Can be Exported?
            Carp::croak("Cannot export '$method'.")
              unless $exports{$method};
            
            # Export
            no strict 'refs';
            *{"${caller}::$method"} = \&{"$method"};
        }
    }
}

sub new {
  my $class = shift;
  bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;
}

sub attr {
    my ($self, @args) = @_;
    
    my $class = ref $self || $self;
    
    # Fix argument
    unshift @args, (shift @args, undef) if @args % 2;
    
    for (my $i = 0; $i < @args; $i += 2) {
        
        # Attribute name
        my $attrs = $args[$i];
        $attrs = [$attrs] unless ref $attrs eq 'ARRAY';
        
        # Default
        my $default = $args[$i + 1];
        
        foreach my $attr (@$attrs) {

            Carp::croak("Default value of attr must be string or number " . 
                        "or code reference (${class}::$attr)")
              unless !ref $default || ref $default eq 'CODE';

        # Code
        my $code;
        if (defined $default && ref $default) {



$code = sub {
    if(@_ == 1) {
        return $_[0]->{$attr} = $default->($_[0]) unless exists $_[0]->{$attr};
        return $_[0]->{$attr};
    }
    $_[0]->{$attr} = $_[1];
    $_[0];
}

        }
        elsif (defined $default && ! ref $default) {



$code = sub {
    if(@_ == 1) {
        return $_[0]->{$attr} = $default unless exists $_[0]->{$attr};
        return $_[0]->{$attr};
    }
    $_[0]->{$attr} = $_[1];
    $_[0];
}



    }
    else {



$code = sub {
    return $_[0]->{$attr} if @_ == 1;
    $_[0]->{$attr} = $_[1];
    $_[0];
}



    }
            
            no strict 'refs';
            *{"${class}::$attr"} = $code;
        }
    }
}

package
  Test::ModuleVersion::HTTP::Tiny;
use strict;
use warnings;
# ABSTRACT: A small, simple, correct HTTP/1.1 client
our $VERSION = '0.016'; # VERSION

use Carp ();


my @attributes;
BEGIN {
    @attributes = qw(agent default_headers max_redirect max_size proxy timeout);
    no strict 'refs';
    for my $accessor ( @attributes ) {
        *{$accessor} = sub {
            @_ > 1 ? $_[0]->{$accessor} = $_[1] : $_[0]->{$accessor};
        };
    }
}

sub new {
    my($class, %args) = @_;
    (my $agent = $class) =~ s{::}{-}g;
    my $self = {
        agent        => $agent . "/" . ($class->VERSION || 0),
        max_redirect => 5,
        timeout      => 60,
    };
    for my $key ( @attributes ) {
        $self->{$key} = $args{$key} if exists $args{$key}
    }

    # Never override proxy argument as this breaks backwards compat.
    if (!exists $self->{proxy} && (my $http_proxy = $ENV{http_proxy})) {
        if ($http_proxy =~ m{\Ahttp://[^/?#:@]+:\d+/?\z}) {
            $self->{proxy} = $http_proxy;
        }
        else {
            Carp::croak(qq{Environment 'http_proxy' must be in format http://<host>:<port>/\n});
        }
    }

    return bless $self, $class;
}


for my $sub_name ( qw/get head put post delete/ ) {
    my $req_method = uc $sub_name;
    no strict 'refs';
    eval <<"HERE";
    sub $sub_name {
        my (\$self, \$url, \$args) = \@_;
        \@_ == 2 || (\@_ == 3 && ref \$args eq 'HASH')
        or Carp::croak(q/Usage: \$http->$sub_name(URL, [HASHREF])/ . "\n");
        return \$self->request('$req_method', \$url, \$args || {});
    }
HERE
}


sub post_form {
    my ($self, $url, $data, $args) = @_;
    (@_ == 3 || @_ == 4 && ref $args eq 'HASH')
        or Carp::croak(q/Usage: $http->post_form(URL, DATAREF, [HASHREF])/ . "\n");

    my $headers = {};
    while ( my ($key, $value) = each %{$args->{headers} || {}} ) {
        $headers->{lc $key} = $value;
    }
    delete $args->{headers};

    return $self->request('POST', $url, {
            %$args,
            content => $self->www_form_urlencode($data),
            headers => {
                %$headers,
                'content-type' => 'application/x-www-form-urlencoded'
            },
        }
    );
}


sub mirror {
    my ($self, $url, $file, $args) = @_;
    @_ == 3 || (@_ == 4 && ref $args eq 'HASH')
      or Carp::croak(q/Usage: $http->mirror(URL, FILE, [HASHREF])/ . "\n");
    if ( -e $file and my $mtime = (stat($file))[9] ) {
        $args->{headers}{'if-modified-since'} ||= $self->_http_date($mtime);
    }
    my $tempfile = $file . int(rand(2**31));
    open my $fh, ">", $tempfile
        or Carp::croak(qq/Error: Could not open temporary file $tempfile for downloading: $!\n/);
    binmode $fh;
    $args->{data_callback} = sub { print {$fh} $_[0] };
    my $response = $self->request('GET', $url, $args);
    close $fh
        or Carp::croak(qq/Error: Could not close temporary file $tempfile: $!\n/);
    if ( $response->{success} ) {
        rename $tempfile, $file
            or Carp::croak(qq/Error replacing $file with $tempfile: $!\n/);
        my $lm = $response->{headers}{'last-modified'};
        if ( $lm and my $mtime = $self->_parse_http_date($lm) ) {
            utime $mtime, $mtime, $file;
        }
    }
    $response->{success} ||= $response->{status} eq '304';
    unlink $tempfile;
    return $response;
}


my %idempotent = map { $_ => 1 } qw/GET HEAD PUT DELETE OPTIONS TRACE/;

sub request {
    my ($self, $method, $url, $args) = @_;
    @_ == 3 || (@_ == 4 && ref $args eq 'HASH')
      or Carp::croak(q/Usage: $http->request(METHOD, URL, [HASHREF])/ . "\n");
    $args ||= {}; # we keep some state in this during _request

    # RFC 2616 Section 8.1.4 mandates a single retry on broken socket
    my $response;
    for ( 0 .. 1 ) {
        $response = eval { $self->_request($method, $url, $args) };
        last unless $@ && $idempotent{$method}
            && $@ =~ m{^(?:Socket closed|Unexpected end)};
    }

    if (my $e = "$@") {
        $response = {
            success => q{},
            status  => 599,
            reason  => 'Internal Exception',
            content => $e,
            headers => {
                'content-type'   => 'text/plain',
                'content-length' => length $e,
            }
        };
    }
    return $response;
}


sub www_form_urlencode {
    my ($self, $data) = @_;
    (@_ == 2 && ref $data)
        or Carp::croak(q/Usage: $http->www_form_urlencode(DATAREF)/ . "\n");
    (ref $data eq 'HASH' || ref $data eq 'ARRAY')
        or Carp::croak("form data must be a hash or array reference");

    my @params = ref $data eq 'HASH' ? %$data : @$data;
    @params % 2 == 0
        or Carp::croak("form data reference must have an even number of terms\n");

    my @terms;
    while( @params ) {
        my ($key, $value) = splice(@params, 0, 2);
        if ( ref $value eq 'ARRAY' ) {
            unshift @params, map { $key => $_ } @$value;
        }
        else {
            push @terms, join("=", map { $self->_uri_escape($_) } $key, $value);
        }
    }

    return join("&", sort @terms);
}

#--------------------------------------------------------------------------#
# private methods
#--------------------------------------------------------------------------#

my %DefaultPort = (
    http => 80,
    https => 443,
);

sub _request {
    my ($self, $method, $url, $args) = @_;

    my ($scheme, $host, $port, $path_query) = $self->_split_url($url);

    my $request = {
        method    => $method,
        scheme    => $scheme,
        host_port => ($port == $DefaultPort{$scheme} ? $host : "$host:$port"),
        uri       => $path_query,
        headers   => {},
    };

    my $handle  = Test::ModuleVersion::HTTP::Tiny::Handle->new(timeout => $self->{timeout});

    if ($self->{proxy}) {
        $request->{uri} = "$scheme://$request->{host_port}$path_query";
        die(qq/HTTPS via proxy is not supported\n/)
            if $request->{scheme} eq 'https';
        $handle->connect(($self->_split_url($self->{proxy}))[0..2]);
    }
    else {
        $handle->connect($scheme, $host, $port);
    }

    $self->_prepare_headers_and_cb($request, $args);
    $handle->write_request($request);

    my $response;
    do { $response = $handle->read_response_header }
        until (substr($response->{status},0,1) ne '1');

    if ( my @redir_args = $self->_maybe_redirect($request, $response, $args) ) {
        $handle->close;
        return $self->_request(@redir_args, $args);
    }

    if ($method eq 'HEAD' || $response->{status} =~ /^[23]04/) {
        # response has no message body
    }
    else {
        my $data_cb = $self->_prepare_data_cb($response, $args);
        $handle->read_body($data_cb, $response);
    }

    $handle->close;
    $response->{success} = substr($response->{status},0,1) eq '2';
    return $response;
}

sub _prepare_headers_and_cb {
    my ($self, $request, $args) = @_;

    for ($self->{default_headers}, $args->{headers}) {
        next unless defined;
        while (my ($k, $v) = each %$_) {
            $request->{headers}{lc $k} = $v;
        }
    }
    $request->{headers}{'host'}         = $request->{host_port};
    $request->{headers}{'connection'}   = "close";
    $request->{headers}{'user-agent'} ||= $self->{agent};

    if (defined $args->{content}) {
        $request->{headers}{'content-type'} ||= "application/octet-stream";
        if (ref $args->{content} eq 'CODE') {
            $request->{headers}{'transfer-encoding'} = 'chunked'
              unless $request->{headers}{'content-length'}
                  || $request->{headers}{'transfer-encoding'};
            $request->{cb} = $args->{content};
        }
        else {
            my $content = $args->{content};
            if ( $] ge '5.008' ) {
                utf8::downgrade($content, 1)
                    or die(qq/Wide character in request message body\n/);
            }
            $request->{headers}{'content-length'} = length $content
              unless $request->{headers}{'content-length'}
                  || $request->{headers}{'transfer-encoding'};
            $request->{cb} = sub { substr $content, 0, length $content, '' };
        }
        $request->{trailer_cb} = $args->{trailer_callback}
            if ref $args->{trailer_callback} eq 'CODE';
    }
    return;
}

sub _prepare_data_cb {
    my ($self, $response, $args) = @_;
    my $data_cb = $args->{data_callback};
    $response->{content} = '';

    if (!$data_cb || $response->{status} !~ /^2/) {
        if (defined $self->{max_size}) {
            $data_cb = sub {
                $_[1]->{content} .= $_[0];
                die(qq/Size of response body exceeds the maximum allowed of $self->{max_size}\n/)
                  if length $_[1]->{content} > $self->{max_size};
            };
        }
        else {
            $data_cb = sub { $_[1]->{content} .= $_[0] };
        }
    }
    return $data_cb;
}

sub _maybe_redirect {
    my ($self, $request, $response, $args) = @_;
    my $headers = $response->{headers};
    my ($status, $method) = ($response->{status}, $request->{method});
    if (($status eq '303' or ($status =~ /^30[127]/ && $method =~ /^GET|HEAD$/))
        and $headers->{location}
        and ++$args->{redirects} <= $self->{max_redirect}
    ) {
        my $location = ($headers->{location} =~ /^\//)
            ? "$request->{scheme}://$request->{host_port}$headers->{location}"
            : $headers->{location} ;
        return (($status eq '303' ? 'GET' : $method), $location);
    }
    return;
}

sub _split_url {
    my $url = pop;

    # URI regex adapted from the URI module
    my ($scheme, $authority, $path_query) = $url =~ m<\A([^:/?#]+)://([^/?#]*)([^#]*)>
      or die(qq/Cannot parse URL: '$url'\n/);

    $scheme     = lc $scheme;
    $path_query = "/$path_query" unless $path_query =~ m<\A/>;

    my $host = (length($authority)) ? lc $authority : 'localhost';
       $host =~ s/\A[^@]*@//;   # userinfo
    my $port = do {
       $host =~ s/:([0-9]*)\z// && length $1
         ? $1
         : ($scheme eq 'http' ? 80 : $scheme eq 'https' ? 443 : undef);
    };

    return ($scheme, $host, $port, $path_query);
}

# Date conversions adapted from HTTP::Date
my $DoW = "Sun|Mon|Tue|Wed|Thu|Fri|Sat";
my $MoY = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec";
sub _http_date {
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($_[1]);
    return sprintf("%s, %02d %s %04d %02d:%02d:%02d GMT",
        substr($DoW,$wday*4,3),
        $mday, substr($MoY,$mon*4,3), $year+1900,
        $hour, $min, $sec
    );
}

sub _parse_http_date {
    my ($self, $str) = @_;
    require Time::Local;
    my @tl_parts;
    if ($str =~ /^[SMTWF][a-z]+, +(\d{1,2}) ($MoY) +(\d\d\d\d) +(\d\d):(\d\d):(\d\d) +GMT$/) {
        @tl_parts = ($6, $5, $4, $1, (index($MoY,$2)/4), $3);
    }
    elsif ($str =~ /^[SMTWF][a-z]+, +(\d\d)-($MoY)-(\d{2,4}) +(\d\d):(\d\d):(\d\d) +GMT$/ ) {
        @tl_parts = ($6, $5, $4, $1, (index($MoY,$2)/4), $3);
    }
    elsif ($str =~ /^[SMTWF][a-z]+ +($MoY) +(\d{1,2}) +(\d\d):(\d\d):(\d\d) +(?:[^0-9]+ +)?(\d\d\d\d)$/ ) {
        @tl_parts = ($5, $4, $3, $2, (index($MoY,$1)/4), $6);
    }
    return eval {
        my $t = @tl_parts ? Time::Local::timegm(@tl_parts) : -1;
        $t < 0 ? undef : $t;
    };
}

# URI escaping adapted from URI::Escape
# c.f. http://www.w3.org/TR/html4/interact/forms.html#h-17.13.4.1
# perl 5.6 ready UTF-8 encoding adapted from Test::ModuleVersion::JSON::PP
my %escapes = map { chr($_) => sprintf("%%%02X", $_) } 0..255;
$escapes{' '}="+";
my $unsafe_char = qr/[^A-Za-z0-9\-\._~]/;

sub _uri_escape {
    my ($self, $str) = @_;
    if ( $] ge '5.008' ) {
        utf8::encode($str);
    }
    else {
        $str = pack("U*", unpack("C*", $str)) # UTF-8 encode a byte string
            if ( length $str == do { use bytes; length $str } );
        $str = pack("C*", unpack("C*", $str)); # clear UTF-8 flag
    }
    $str =~ s/($unsafe_char)/$escapes{$1}/ge;
    return $str;
}

package
    Test::ModuleVersion::HTTP::Tiny::Handle; # hide from PAUSE/indexers
use strict;
use warnings;

use Errno      qw[EINTR EPIPE];
use IO::Socket qw[SOCK_STREAM];

sub BUFSIZE () { 32768 }

my $Printable = sub {
    local $_ = shift;
    s/\r/\\r/g;
    s/\n/\\n/g;
    s/\t/\\t/g;
    s/([^\x20-\x7E])/sprintf('\\x%.2X', ord($1))/ge;
    $_;
};

my $Token = qr/[\x21\x23-\x27\x2A\x2B\x2D\x2E\x30-\x39\x41-\x5A\x5E-\x7A\x7C\x7E]/;

sub new {
    my ($class, %args) = @_;
    return bless {
        rbuf             => '',
        timeout          => 60,
        max_line_size    => 16384,
        max_header_lines => 64,
        %args
    }, $class;
}

my $ssl_verify_args = {
    check_cn => "when_only",
    wildcards_in_alt => "anywhere",
    wildcards_in_cn => "anywhere"
};

sub connect {
    @_ == 4 || die(q/Usage: $handle->connect(scheme, host, port)/ . "\n");
    my ($self, $scheme, $host, $port) = @_;

    if ( $scheme eq 'https' ) {
        eval "require IO::Socket::SSL"
            unless exists $INC{'IO/Socket/SSL.pm'};
        die(qq/IO::Socket::SSL must be installed for https support\n/)
            unless $INC{'IO/Socket/SSL.pm'};
    }
    elsif ( $scheme ne 'http' ) {
      die(qq/Unsupported URL scheme '$scheme'\n/);
    }

    $self->{fh} = 'IO::Socket::INET'->new(
        PeerHost  => $host,
        PeerPort  => $port,
        Proto     => 'tcp',
        Type      => SOCK_STREAM,
        Timeout   => $self->{timeout}
    ) or die(qq/Could not connect to '$host:$port': $@\n/);

    binmode($self->{fh})
      or die(qq/Could not binmode() socket: '$!'\n/);

    if ( $scheme eq 'https') {
        IO::Socket::SSL->start_SSL($self->{fh});
        ref($self->{fh}) eq 'IO::Socket::SSL'
            or die(qq/SSL connection failed for $host\n/);
        $self->{fh}->verify_hostname( $host, $ssl_verify_args )
            or die(qq/SSL certificate not valid for $host\n/);
    }

    $self->{host} = $host;
    $self->{port} = $port;

    return $self;
}

sub close {
    @_ == 1 || die(q/Usage: $handle->close()/ . "\n");
    my ($self) = @_;
    CORE::close($self->{fh})
      or die(qq/Could not close socket: '$!'\n/);
}

sub write {
    @_ == 2 || die(q/Usage: $handle->write(buf)/ . "\n");
    my ($self, $buf) = @_;

    if ( $] ge '5.008' ) {
        utf8::downgrade($buf, 1)
            or die(qq/Wide character in write()\n/);
    }

    my $len = length $buf;
    my $off = 0;

    local $SIG{PIPE} = 'IGNORE';

    while () {
        $self->can_write
          or die(qq/Timed out while waiting for socket to become ready for writing\n/);
        my $r = syswrite($self->{fh}, $buf, $len, $off);
        if (defined $r) {
            $len -= $r;
            $off += $r;
            last unless $len > 0;
        }
        elsif ($! == EPIPE) {
            die(qq/Socket closed by remote server: $!\n/);
        }
        elsif ($! != EINTR) {
            die(qq/Could not write to socket: '$!'\n/);
        }
    }
    return $off;
}

sub read {
    @_ == 2 || @_ == 3 || die(q/Usage: $handle->read(len [, allow_partial])/ . "\n");
    my ($self, $len, $allow_partial) = @_;

    my $buf  = '';
    my $got = length $self->{rbuf};

    if ($got) {
        my $take = ($got < $len) ? $got : $len;
        $buf  = substr($self->{rbuf}, 0, $take, '');
        $len -= $take;
    }

    while ($len > 0) {
        $self->can_read
          or die(q/Timed out while waiting for socket to become ready for reading/ . "\n");
        my $r = sysread($self->{fh}, $buf, $len, length $buf);
        if (defined $r) {
            last unless $r;
            $len -= $r;
        }
        elsif ($! != EINTR) {
            die(qq/Could not read from socket: '$!'\n/);
        }
    }
    if ($len && !$allow_partial) {
        die(qq/Unexpected end of stream\n/);
    }
    return $buf;
}

sub readline {
    @_ == 1 || die(q/Usage: $handle->readline()/ . "\n");
    my ($self) = @_;

    while () {
        if ($self->{rbuf} =~ s/\A ([^\x0D\x0A]* \x0D?\x0A)//x) {
            return $1;
        }
        if (length $self->{rbuf} >= $self->{max_line_size}) {
            die(qq/Line size exceeds the maximum allowed size of $self->{max_line_size}\n/);
        }
        $self->can_read
          or die(qq/Timed out while waiting for socket to become ready for reading\n/);
        my $r = sysread($self->{fh}, $self->{rbuf}, BUFSIZE, length $self->{rbuf});
        if (defined $r) {
            last unless $r;
        }
        elsif ($! != EINTR) {
            die(qq/Could not read from socket: '$!'\n/);
        }
    }
    die(qq/Unexpected end of stream while looking for line\n/);
}

sub read_header_lines {
    @_ == 1 || @_ == 2 || die(q/Usage: $handle->read_header_lines([headers])/ . "\n");
    my ($self, $headers) = @_;
    $headers ||= {};
    my $lines   = 0;
    my $val;

    while () {
         my $line = $self->readline;

         if (++$lines >= $self->{max_header_lines}) {
             die(qq/Header lines exceeds maximum number allowed of $self->{max_header_lines}\n/);
         }
         elsif ($line =~ /\A ([^\x00-\x1F\x7F:]+) : [\x09\x20]* ([^\x0D\x0A]*)/x) {
             my ($field_name) = lc $1;
             if (exists $headers->{$field_name}) {
                 for ($headers->{$field_name}) {
                     $_ = [$_] unless ref $_ eq "ARRAY";
                     push @$_, $2;
                     $val = \$_->[-1];
                 }
             }
             else {
                 $val = \($headers->{$field_name} = $2);
             }
         }
         elsif ($line =~ /\A [\x09\x20]+ ([^\x0D\x0A]*)/x) {
             $val
               or die(qq/Unexpected header continuation line\n/);
             next unless length $1;
             $$val .= ' ' if length $$val;
             $$val .= $1;
         }
         elsif ($line =~ /\A \x0D?\x0A \z/x) {
            last;
         }
         else {
            die(q/Malformed header line: / . $Printable->($line) . "\n");
         }
    }
    return $headers;
}

sub write_request {
    @_ == 2 || die(q/Usage: $handle->write_request(request)/ . "\n");
    my($self, $request) = @_;
    $self->write_request_header(@{$request}{qw/method uri headers/});
    $self->write_body($request) if $request->{cb};
    return;
}

my %HeaderCase = (
    'content-md5'      => 'Content-MD5',
    'etag'             => 'ETag',
    'te'               => 'TE',
    'www-authenticate' => 'WWW-Authenticate',
    'x-xss-protection' => 'X-XSS-Protection',
);

sub write_header_lines {
    (@_ == 2 && ref $_[1] eq 'HASH') || die(q/Usage: $handle->write_header_lines(headers)/ . "\n");
    my($self, $headers) = @_;

    my $buf = '';
    while (my ($k, $v) = each %$headers) {
        my $field_name = lc $k;
        if (exists $HeaderCase{$field_name}) {
            $field_name = $HeaderCase{$field_name};
        }
        else {
            $field_name =~ /\A $Token+ \z/xo
              or die(q/Invalid HTTP header field name: / . $Printable->($field_name) . "\n");
            $field_name =~ s/\b(\w)/\u$1/g;
            $HeaderCase{lc $field_name} = $field_name;
        }
        for (ref $v eq 'ARRAY' ? @$v : $v) {
            /[^\x0D\x0A]/
              or die(qq/Invalid HTTP header field value ($field_name): / . $Printable->($_). "\n");
            $buf .= "$field_name: $_\x0D\x0A";
        }
    }
    $buf .= "\x0D\x0A";
    return $self->write($buf);
}

sub read_body {
    @_ == 3 || die(q/Usage: $handle->read_body(callback, response)/ . "\n");
    my ($self, $cb, $response) = @_;
    my $te = $response->{headers}{'transfer-encoding'} || '';
    if ( grep { /chunked/i } ( ref $te eq 'ARRAY' ? @$te : $te ) ) {
        $self->read_chunked_body($cb, $response);
    }
    else {
        $self->read_content_body($cb, $response);
    }
    return;
}

sub write_body {
    @_ == 2 || die(q/Usage: $handle->write_body(request)/ . "\n");
    my ($self, $request) = @_;
    if ($request->{headers}{'content-length'}) {
        return $self->write_content_body($request);
    }
    else {
        return $self->write_chunked_body($request);
    }
}

sub read_content_body {
    @_ == 3 || @_ == 4 || die(q/Usage: $handle->read_content_body(callback, response, [read_length])/ . "\n");
    my ($self, $cb, $response, $content_length) = @_;
    $content_length ||= $response->{headers}{'content-length'};

    if ( $content_length ) {
        my $len = $content_length;
        while ($len > 0) {
            my $read = ($len > BUFSIZE) ? BUFSIZE : $len;
            $cb->($self->read($read, 0), $response);
            $len -= $read;
        }
    }
    else {
        my $chunk;
        $cb->($chunk, $response) while length( $chunk = $self->read(BUFSIZE, 1) );
    }

    return;
}

sub write_content_body {
    @_ == 2 || die(q/Usage: $handle->write_content_body(request)/ . "\n");
    my ($self, $request) = @_;

    my ($len, $content_length) = (0, $request->{headers}{'content-length'});
    while () {
        my $data = $request->{cb}->();

        defined $data && length $data
          or last;

        if ( $] ge '5.008' ) {
            utf8::downgrade($data, 1)
                or die(qq/Wide character in write_content()\n/);
        }

        $len += $self->write($data);
    }

    $len == $content_length
      or die(qq/Content-Length missmatch (got: $len expected: $content_length)\n/);

    return $len;
}

sub read_chunked_body {
    @_ == 3 || die(q/Usage: $handle->read_chunked_body(callback, $response)/ . "\n");
    my ($self, $cb, $response) = @_;

    while () {
        my $head = $self->readline;

        $head =~ /\A ([A-Fa-f0-9]+)/x
          or die(q/Malformed chunk head: / . $Printable->($head) . "\n");

        my $len = hex($1)
          or last;

        $self->read_content_body($cb, $response, $len);

        $self->read(2) eq "\x0D\x0A"
          or die(qq/Malformed chunk: missing CRLF after chunk data\n/);
    }
    $self->read_header_lines($response->{headers});
    return;
}

sub write_chunked_body {
    @_ == 2 || die(q/Usage: $handle->write_chunked_body(request)/ . "\n");
    my ($self, $request) = @_;

    my $len = 0;
    while () {
        my $data = $request->{cb}->();

        defined $data && length $data
          or last;

        if ( $] ge '5.008' ) {
            utf8::downgrade($data, 1)
                or die(qq/Wide character in write_chunked_body()\n/);
        }

        $len += length $data;

        my $chunk  = sprintf '%X', length $data;
           $chunk .= "\x0D\x0A";
           $chunk .= $data;
           $chunk .= "\x0D\x0A";

        $self->write($chunk);
    }
    $self->write("0\x0D\x0A");
    $self->write_header_lines($request->{trailer_cb}->())
        if ref $request->{trailer_cb} eq 'CODE';
    return $len;
}

sub read_response_header {
    @_ == 1 || die(q/Usage: $handle->read_response_header()/ . "\n");
    my ($self) = @_;

    my $line = $self->readline;

    $line =~ /\A (HTTP\/(0*\d+\.0*\d+)) [\x09\x20]+ ([0-9]{3}) [\x09\x20]+ ([^\x0D\x0A]*) \x0D?\x0A/x
      or die(q/Malformed Status-Line: / . $Printable->($line). "\n");

    my ($protocol, $version, $status, $reason) = ($1, $2, $3, $4);

    die (qq/Unsupported HTTP protocol: $protocol\n/)
        unless $version =~ /0*1\.0*[01]/;

    return {
        status   => $status,
        reason   => $reason,
        headers  => $self->read_header_lines,
        protocol => $protocol,
    };
}

sub write_request_header {
    @_ == 4 || die(q/Usage: $handle->write_request_header(method, request_uri, headers)/ . "\n");
    my ($self, $method, $request_uri, $headers) = @_;

    return $self->write("$method $request_uri HTTP/1.1\x0D\x0A")
         + $self->write_header_lines($headers);
}

sub _do_timeout {
    my ($self, $type, $timeout) = @_;
    $timeout = $self->{timeout}
        unless defined $timeout && $timeout >= 0;

    my $fd = fileno $self->{fh};
    defined $fd && $fd >= 0
      or die(qq/select(2): 'Bad file descriptor'\n/);

    my $initial = time;
    my $pending = $timeout;
    my $nfound;

    vec(my $fdset = '', $fd, 1) = 1;

    while () {
        $nfound = ($type eq 'read')
            ? select($fdset, undef, undef, $pending)
            : select(undef, $fdset, undef, $pending) ;
        if ($nfound == -1) {
            $! == EINTR
              or die(qq/select(2): '$!'\n/);
            redo if !$timeout || ($pending = $timeout - (time - $initial)) > 0;
            $nfound = 0;
        }
        last;
    }
    $! = 0;
    return $nfound;
}

sub can_read {
    @_ == 1 || @_ == 2 || die(q/Usage: $handle->can_read([timeout])/ . "\n");
    my $self = shift;
    return $self->_do_timeout('read', @_)
}

sub can_write {
    @_ == 1 || @_ == 2 || die(q/Usage: $handle->can_write([timeout])/ . "\n");
    my $self = shift;
    return $self->_do_timeout('write', @_)
}

no warnings 'once';
package Test::ModuleVersion::JSON::PP;
# JSON-2.0

use 5.005;
use strict;
use base qw(Exporter);
use overload ();

use Carp ();
use B ();
#use Devel::Peek;

$Test::ModuleVersion::JSON::PP::VERSION = '2.27200';

@Test::ModuleVersion::JSON::PP::EXPORT = qw(encode_json decode_json from_json to_json);

# instead of hash-access, i tried index-access for speed.
# but this method is not faster than what i expected. so it will be changed.

use constant P_ASCII                => 0;
use constant P_LATIN1               => 1;
use constant P_UTF8                 => 2;
use constant P_INDENT               => 3;
use constant P_CANONICAL            => 4;
use constant P_SPACE_BEFORE         => 5;
use constant P_SPACE_AFTER          => 6;
use constant P_ALLOW_NONREF         => 7;
use constant P_SHRINK               => 8;
use constant P_ALLOW_BLESSED        => 9;
use constant P_CONVERT_BLESSED      => 10;
use constant P_RELAXED              => 11;

use constant P_LOOSE                => 12;
use constant P_ALLOW_BIGNUM         => 13;
use constant P_ALLOW_BAREKEY        => 14;
use constant P_ALLOW_SINGLEQUOTE    => 15;
use constant P_ESCAPE_SLASH         => 16;
use constant P_AS_NONBLESSED        => 17;

use constant P_ALLOW_UNKNOWN        => 18;

use constant OLD_PERL => $] < 5.008 ? 1 : 0;

BEGIN {
    my @xs_compati_bit_properties = qw(
            latin1 ascii utf8 indent canonical space_before space_after allow_nonref shrink
            allow_blessed convert_blessed relaxed allow_unknown
    );
    my @pp_bit_properties = qw(
            allow_singlequote allow_bignum loose
            allow_barekey escape_slash as_nonblessed
    );

    # Perl version check, Unicode handling is enable?
    # Helper module sets @Test::ModuleVersion::JSON::PP::_properties.
    if ($] < 5.008 ) {
        my $helper = $] >= 5.006 ? 'Test::ModuleVersion::JSON::PP::Compat5006' : 'Test::ModuleVersion::JSON::PP::Compat5005';
        eval qq| require $helper |;
        if ($@) { Carp::croak $@; }
    }

    for my $name (@xs_compati_bit_properties, @pp_bit_properties) {
        my $flag_name = 'P_' . uc($name);

        eval qq/
            sub $name {
                my \$enable = defined \$_[1] ? \$_[1] : 1;

                if (\$enable) {
                    \$_[0]->{PROPS}->[$flag_name] = 1;
                }
                else {
                    \$_[0]->{PROPS}->[$flag_name] = 0;
                }

                \$_[0];
            }

            sub get_$name {
                \$_[0]->{PROPS}->[$flag_name] ? 1 : '';
            }
        /;
    }

}



# Functions

my %encode_allow_method
     = map {($_ => 1)} qw/utf8 pretty allow_nonref latin1 self_encode escape_slash
                          allow_blessed convert_blessed indent indent_length allow_bignum
                          as_nonblessed
                        /;
my %decode_allow_method
     = map {($_ => 1)} qw/utf8 allow_nonref loose allow_singlequote allow_bignum
                          allow_barekey max_size relaxed/;


my $JSON; # cache

sub encode_json ($) { # encode
    ($JSON ||= __PACKAGE__->new->utf8)->encode(@_);
}


sub decode_json { # decode
    ($JSON ||= __PACKAGE__->new->utf8)->decode(@_);
}

# Obsoleted

sub to_json($) {
   Carp::croak ("Test::ModuleVersion::JSON::PP::to_json has been renamed to encode_json.");
}


sub from_json($) {
   Carp::croak ("Test::ModuleVersion::JSON::PP::from_json has been renamed to decode_json.");
}


# Methods

sub new {
    my $class = shift;
    my $self  = {
        max_depth   => 512,
        max_size    => 0,
        indent      => 0,
        FLAGS       => 0,
        fallback      => sub { encode_error('Invalid value. JSON can only reference.') },
        indent_length => 3,
    };

    bless $self, $class;
}


sub encode {
    return $_[0]->PP_encode_json($_[1]);
}


sub decode {
    return $_[0]->PP_decode_json($_[1], 0x00000000);
}


sub decode_prefix {
    return $_[0]->PP_decode_json($_[1], 0x00000001);
}


# accessor


# pretty printing

sub pretty {
    my ($self, $v) = @_;
    my $enable = defined $v ? $v : 1;

    if ($enable) { # indent_length(3) for JSON::XS compatibility
        $self->indent(1)->indent_length(3)->space_before(1)->space_after(1);
    }
    else {
        $self->indent(0)->space_before(0)->space_after(0);
    }

    $self;
}

# etc

sub max_depth {
    my $max  = defined $_[1] ? $_[1] : 0x80000000;
    $_[0]->{max_depth} = $max;
    $_[0];
}


sub get_max_depth { $_[0]->{max_depth}; }


sub max_size {
    my $max  = defined $_[1] ? $_[1] : 0;
    $_[0]->{max_size} = $max;
    $_[0];
}


sub get_max_size { $_[0]->{max_size}; }


sub filter_json_object {
    $_[0]->{cb_object} = defined $_[1] ? $_[1] : 0;
    $_[0]->{F_HOOK} = ($_[0]->{cb_object} or $_[0]->{cb_sk_object}) ? 1 : 0;
    $_[0];
}

sub filter_json_single_key_object {
    if (@_ > 1) {
        $_[0]->{cb_sk_object}->{$_[1]} = $_[2];
    }
    $_[0]->{F_HOOK} = ($_[0]->{cb_object} or $_[0]->{cb_sk_object}) ? 1 : 0;
    $_[0];
}

sub indent_length {
    if (!defined $_[1] or $_[1] > 15 or $_[1] < 0) {
        Carp::carp "The acceptable range of indent_length() is 0 to 15.";
    }
    else {
        $_[0]->{indent_length} = $_[1];
    }
    $_[0];
}

sub get_indent_length {
    $_[0]->{indent_length};
}

sub sort_by {
    $_[0]->{sort_by} = defined $_[1] ? $_[1] : 1;
    $_[0];
}

sub allow_bigint {
    Carp::carp("allow_bigint() is obsoleted. use allow_bignum() insted.");
}

###############################

###
### Perl => JSON
###


{ # Convert

    my $max_depth;
    my $indent;
    my $ascii;
    my $latin1;
    my $utf8;
    my $space_before;
    my $space_after;
    my $canonical;
    my $allow_blessed;
    my $convert_blessed;

    my $indent_length;
    my $escape_slash;
    my $bignum;
    my $as_nonblessed;

    my $depth;
    my $indent_count;
    my $keysort;


    sub PP_encode_json {
        my $self = shift;
        my $obj  = shift;

        $indent_count = 0;
        $depth        = 0;

        my $idx = $self->{PROPS};

        ($ascii, $latin1, $utf8, $indent, $canonical, $space_before, $space_after, $allow_blessed,
            $convert_blessed, $escape_slash, $bignum, $as_nonblessed)
         = @{$idx}[P_ASCII .. P_SPACE_AFTER, P_ALLOW_BLESSED, P_CONVERT_BLESSED,
                    P_ESCAPE_SLASH, P_ALLOW_BIGNUM, P_AS_NONBLESSED];

        ($max_depth, $indent_length) = @{$self}{qw/max_depth indent_length/};

        $keysort = $canonical ? sub { $a cmp $b } : undef;

        if ($self->{sort_by}) {
            $keysort = ref($self->{sort_by}) eq 'CODE' ? $self->{sort_by}
                     : $self->{sort_by} =~ /\D+/       ? $self->{sort_by}
                     : sub { $a cmp $b };
        }

        encode_error("hash- or arrayref expected (not a simple scalar, use allow_nonref to allow this)")
             if(!ref $obj and !$idx->[ P_ALLOW_NONREF ]);

        my $str  = $self->object_to_json($obj);

        $str .= "\n" if ( $indent ); # JSON::XS 2.26 compatible

        unless ($ascii or $latin1 or $utf8) {
            utf8::upgrade($str);
        }

        if ($idx->[ P_SHRINK ]) {
            utf8::downgrade($str, 1);
        }

        return $str;
    }


    sub object_to_json {
        my ($self, $obj) = @_;
        my $type = ref($obj);

        if($type eq 'HASH'){
            return $self->hash_to_json($obj);
        }
        elsif($type eq 'ARRAY'){
            return $self->array_to_json($obj);
        }
        elsif ($type) { # blessed object?
            if (blessed($obj)) {

                return $self->value_to_json($obj) if ( $obj->isa('Test::ModuleVersion::JSON::PP::Boolean') );

                if ( $convert_blessed and $obj->can('TO_JSON') ) {
                    my $result = $obj->TO_JSON();
                    if ( defined $result and ref( $result ) ) {
                        if ( refaddr( $obj ) eq refaddr( $result ) ) {
                            encode_error( sprintf(
                                "%s::TO_JSON method returned same object as was passed instead of a new one",
                                ref $obj
                            ) );
                        }
                    }

                    return $self->object_to_json( $result );
                }

                return "$obj" if ( $bignum and _is_bignum($obj) );
                return $self->blessed_to_json($obj) if ($allow_blessed and $as_nonblessed); # will be removed.

                encode_error( sprintf("encountered object '%s', but neither allow_blessed "
                    . "nor convert_blessed settings are enabled", $obj)
                ) unless ($allow_blessed);

                return 'null';
            }
            else {
                return $self->value_to_json($obj);
            }
        }
        else{
            return $self->value_to_json($obj);
        }
    }


    sub hash_to_json {
        my ($self, $obj) = @_;
        my @res;

        encode_error("json text or perl structure exceeds maximum nesting level (max_depth set too low?)")
                                         if (++$depth > $max_depth);

        my ($pre, $post) = $indent ? $self->_up_indent() : ('', '');
        my $del = ($space_before ? ' ' : '') . ':' . ($space_after ? ' ' : '');

        for my $k ( _sort( $obj ) ) {
            if ( OLD_PERL ) { utf8::decode($k) } # key for Perl 5.6 / be optimized
            push @res, string_to_json( $self, $k )
                          .  $del
                          . ( $self->object_to_json( $obj->{$k} ) || $self->value_to_json( $obj->{$k} ) );
        }

        --$depth;
        $self->_down_indent() if ($indent);

        return   '{' . ( @res ? $pre : '' ) . ( @res ? join( ",$pre", @res ) . $post : '' )  . '}';
    }


    sub array_to_json {
        my ($self, $obj) = @_;
        my @res;

        encode_error("json text or perl structure exceeds maximum nesting level (max_depth set too low?)")
                                         if (++$depth > $max_depth);

        my ($pre, $post) = $indent ? $self->_up_indent() : ('', '');

        for my $v (@$obj){
            push @res, $self->object_to_json($v) || $self->value_to_json($v);
        }

        --$depth;
        $self->_down_indent() if ($indent);

        return '[' . ( @res ? $pre : '' ) . ( @res ? join( ",$pre", @res ) . $post : '' ) . ']';
    }


    sub value_to_json {
        my ($self, $value) = @_;

        return 'null' if(!defined $value);

        my $b_obj = B::svref_2object(\$value);  # for round trip problem
        my $flags = $b_obj->FLAGS;

        return $value # as is 
            if $flags & ( B::SVp_IOK | B::SVp_NOK ) and !( $flags & B::SVp_POK ); # SvTYPE is IV or NV?

        my $type = ref($value);

        if(!$type){
            return string_to_json($self, $value);
        }
        elsif( blessed($value) and  $value->isa('Test::ModuleVersion::JSON::PP::Boolean') ){
            return $$value == 1 ? 'true' : 'false';
        }
        elsif ($type) {
            if ((overload::StrVal($value) =~ /=(\w+)/)[0]) {
                return $self->value_to_json("$value");
            }

            if ($type eq 'SCALAR' and defined $$value) {
                return   $$value eq '1' ? 'true'
                       : $$value eq '0' ? 'false'
                       : $self->{PROPS}->[ P_ALLOW_UNKNOWN ] ? 'null'
                       : encode_error("cannot encode reference to scalar");
            }

             if ( $self->{PROPS}->[ P_ALLOW_UNKNOWN ] ) {
                 return 'null';
             }
             else {
                 if ( $type eq 'SCALAR' or $type eq 'REF' ) {
                    encode_error("cannot encode reference to scalar");
                 }
                 else {
                    encode_error("encountered $value, but JSON can only represent references to arrays or hashes");
                 }
             }

        }
        else {
            return $self->{fallback}->($value)
                 if ($self->{fallback} and ref($self->{fallback}) eq 'CODE');
            return 'null';
        }

    }


    my %esc = (
        "\n" => '\n',
        "\r" => '\r',
        "\t" => '\t',
        "\f" => '\f',
        "\b" => '\b',
        "\"" => '\"',
        "\\" => '\\\\',
        "\'" => '\\\'',
    );


    sub string_to_json {
        my ($self, $arg) = @_;

        $arg =~ s/([\x22\x5c\n\r\t\f\b])/$esc{$1}/g;
        $arg =~ s/\//\\\//g if ($escape_slash);
        $arg =~ s/([\x00-\x08\x0b\x0e-\x1f])/'\\u00' . unpack('H2', $1)/eg;

        if ($ascii) {
            $arg = JSON_PP_encode_ascii($arg);
        }

        if ($latin1) {
            $arg = JSON_PP_encode_latin1($arg);
        }

        if ($utf8) {
            utf8::encode($arg);
        }

        return '"' . $arg . '"';
    }


    sub blessed_to_json {
        my $reftype = reftype($_[1]) || '';
        if ($reftype eq 'HASH') {
            return $_[0]->hash_to_json($_[1]);
        }
        elsif ($reftype eq 'ARRAY') {
            return $_[0]->array_to_json($_[1]);
        }
        else {
            return 'null';
        }
    }


    sub encode_error {
        my $error  = shift;
        Carp::croak "$error";
    }


    sub _sort {
        defined $keysort ? (sort $keysort (keys %{$_[0]})) : keys %{$_[0]};
    }


    sub _up_indent {
        my $self  = shift;
        my $space = ' ' x $indent_length;

        my ($pre,$post) = ('','');

        $post = "\n" . $space x $indent_count;

        $indent_count++;

        $pre = "\n" . $space x $indent_count;

        return ($pre,$post);
    }


    sub _down_indent { $indent_count--; }


    sub PP_encode_box {
        {
            depth        => $depth,
            indent_count => $indent_count,
        };
    }

} # Convert


sub _encode_ascii {
    join('',
        map {
            $_ <= 127 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) : sprintf('\u%x\u%x', _encode_surrogates($_));
        } unpack('U*', $_[0])
    );
}


sub _encode_latin1 {
    join('',
        map {
            $_ <= 255 ?
                chr($_) :
            $_ <= 65535 ?
                sprintf('\u%04x', $_) : sprintf('\u%x\u%x', _encode_surrogates($_));
        } unpack('U*', $_[0])
    );
}


sub _encode_surrogates { # from perlunicode
    my $uni = $_[0] - 0x10000;
    return ($uni / 0x400 + 0xD800, $uni % 0x400 + 0xDC00);
}


sub _is_bignum {
    $_[0]->isa('Math::BigInt') or $_[0]->isa('Math::BigFloat');
}



#
# JSON => Perl
#

my $max_intsize;

BEGIN {
    my $checkint = 1111;
    for my $d (5..64) {
        $checkint .= 1;
        my $int   = eval qq| $checkint |;
        if ($int =~ /[eE]/) {
            $max_intsize = $d - 1;
            last;
        }
    }
}

{ # PARSE 

    my %escapes = ( #  by Jeremy Muhlich <jmuhlich [at] bitflood.org>
        b    => "\x8",
        t    => "\x9",
        n    => "\xA",
        f    => "\xC",
        r    => "\xD",
        '\\' => '\\',
        '"'  => '"',
        '/'  => '/',
    );

    my $text; # json data
    my $at;   # offset
    my $ch;   # 1chracter
    my $len;  # text length (changed according to UTF8 or NON UTF8)
    # INTERNAL
    my $depth;          # nest counter
    my $encoding;       # json text encoding
    my $is_valid_utf8;  # temp variable
    my $utf8_len;       # utf8 byte length
    # FLAGS
    my $utf8;           # must be utf8
    my $max_depth;      # max nest nubmer of objects and arrays
    my $max_size;
    my $relaxed;
    my $cb_object;
    my $cb_sk_object;

    my $F_HOOK;

    my $allow_bigint;   # using Math::BigInt
    my $singlequote;    # loosely quoting
    my $loose;          # 
    my $allow_barekey;  # bareKey

    # $opt flag
    # 0x00000001 .... decode_prefix
    # 0x10000000 .... incr_parse

    sub PP_decode_json {
        my ($self, $opt); # $opt is an effective flag during this decode_json.

        ($self, $text, $opt) = @_;

        ($at, $ch, $depth) = (0, '', 0);

        if ( !defined $text or ref $text ) {
            decode_error("malformed JSON string, neither array, object, number, string or atom");
        }

        my $idx = $self->{PROPS};

        ($utf8, $relaxed, $loose, $allow_bigint, $allow_barekey, $singlequote)
            = @{$idx}[P_UTF8, P_RELAXED, P_LOOSE .. P_ALLOW_SINGLEQUOTE];

        if ( $utf8 ) {
            utf8::downgrade( $text, 1 ) or Carp::croak("Wide character in subroutine entry");
        }
        else {
            utf8::upgrade( $text );
        }

        $len = length $text;

        ($max_depth, $max_size, $cb_object, $cb_sk_object, $F_HOOK)
             = @{$self}{qw/max_depth  max_size cb_object cb_sk_object F_HOOK/};

        if ($max_size > 1) {
            use bytes;
            my $bytes = length $text;
            decode_error(
                sprintf("attempted decode of JSON text of %s bytes size, but max_size is set to %s"
                    , $bytes, $max_size), 1
            ) if ($bytes > $max_size);
        }

        # Currently no effect
        # should use regexp
        my @octets = unpack('C4', $text);
        $encoding =   ( $octets[0] and  $octets[1]) ? 'UTF-8'
                    : (!$octets[0] and  $octets[1]) ? 'UTF-16BE'
                    : (!$octets[0] and !$octets[1]) ? 'UTF-32BE'
                    : ( $octets[2]                ) ? 'UTF-16LE'
                    : (!$octets[2]                ) ? 'UTF-32LE'
                    : 'unknown';

        white(); # remove head white space

        my $valid_start = defined $ch; # Is there a first character for JSON structure?

        my $result = value();

        return undef if ( !$result && ( $opt & 0x10000000 ) ); # for incr_parse

        decode_error("malformed JSON string, neither array, object, number, string or atom") unless $valid_start;

        if ( !$idx->[ P_ALLOW_NONREF ] and !ref $result ) {
                decode_error(
                'JSON text must be an object or array (but found number, string, true, false or null,'
                       . ' use allow_nonref to allow this)', 1);
        }

        Carp::croak('something wrong.') if $len < $at; # we won't arrive here.

        my $consumed = defined $ch ? $at - 1 : $at; # consumed JSON text length

        white(); # remove tail white space

        if ( $ch ) {
            return ( $result, $consumed ) if ($opt & 0x00000001); # all right if decode_prefix
            decode_error("garbage after JSON object");
        }

        ( $opt & 0x00000001 ) ? ( $result, $consumed ) : $result;
    }


    sub next_chr {
        return $ch = undef if($at >= $len);
        $ch = substr($text, $at++, 1);
    }


    sub value {
        white();
        return          if(!defined $ch);
        return object() if($ch eq '{');
        return array()  if($ch eq '[');
        return string() if($ch eq '"' or ($singlequote and $ch eq "'"));
        return number() if($ch =~ /[0-9]/ or $ch eq '-');
        return word();
    }

    sub string {
        my ($i, $s, $t, $u);
        my $utf16;
        my $is_utf8;

        ($is_valid_utf8, $utf8_len) = ('', 0);

        $s = ''; # basically UTF8 flag on

        if($ch eq '"' or ($singlequote and $ch eq "'")){
            my $boundChar = $ch;

            OUTER: while( defined(next_chr()) ){

                if($ch eq $boundChar){
                    next_chr();

                    if ($utf16) {
                        decode_error("missing low surrogate character in surrogate pair");
                    }

                    utf8::decode($s) if($is_utf8);

                    return $s;
                }
                elsif($ch eq '\\'){
                    next_chr();
                    if(exists $escapes{$ch}){
                        $s .= $escapes{$ch};
                    }
                    elsif($ch eq 'u'){ # UNICODE handling
                        my $u = '';

                        for(1..4){
                            $ch = next_chr();
                            last OUTER if($ch !~ /[0-9a-fA-F]/);
                            $u .= $ch;
                        }

                        # U+D800 - U+DBFF
                        if ($u =~ /^[dD][89abAB][0-9a-fA-F]{2}/) { # UTF-16 high surrogate?
                            $utf16 = $u;
                        }
                        # U+DC00 - U+DFFF
                        elsif ($u =~ /^[dD][c-fC-F][0-9a-fA-F]{2}/) { # UTF-16 low surrogate?
                            unless (defined $utf16) {
                                decode_error("missing high surrogate character in surrogate pair");
                            }
                            $is_utf8 = 1;
                            $s .= JSON_PP_decode_surrogates($utf16, $u) || next;
                            $utf16 = undef;
                        }
                        else {
                            if (defined $utf16) {
                                decode_error("surrogate pair expected");
                            }

                            if ( ( my $hex = hex( $u ) ) > 127 ) {
                                $is_utf8 = 1;
                                $s .= JSON_PP_decode_unicode($u) || next;
                            }
                            else {
                                $s .= chr $hex;
                            }
                        }

                    }
                    else{
                        unless ($loose) {
                            $at -= 2;
                            decode_error('illegal backslash escape sequence in string');
                        }
                        $s .= $ch;
                    }
                }
                else{

                    if ( ord $ch  > 127 ) {
                        if ( $utf8 ) {
                            unless( $ch = is_valid_utf8($ch) ) {
                                $at -= 1;
                                decode_error("malformed UTF-8 character in JSON string");
                            }
                            else {
                                $at += $utf8_len - 1;
                            }
                        }
                        else {
                            utf8::encode( $ch );
                        }

                        $is_utf8 = 1;
                    }

                    if (!$loose) {
                        if ($ch =~ /[\x00-\x1f\x22\x5c]/)  { # '/' ok
                            $at--;
                            decode_error('invalid character encountered while parsing JSON string');
                        }
                    }

                    $s .= $ch;
                }
            }
        }

        decode_error("unexpected end of string while parsing JSON string");
    }


    sub white {
        while( defined $ch  ){
            if($ch le ' '){
                next_chr();
            }
            elsif($ch eq '/'){
                next_chr();
                if(defined $ch and $ch eq '/'){
                    1 while(defined(next_chr()) and $ch ne "\n" and $ch ne "\r");
                }
                elsif(defined $ch and $ch eq '*'){
                    next_chr();
                    while(1){
                        if(defined $ch){
                            if($ch eq '*'){
                                if(defined(next_chr()) and $ch eq '/'){
                                    next_chr();
                                    last;
                                }
                            }
                            else{
                                next_chr();
                            }
                        }
                        else{
                            decode_error("Unterminated comment");
                        }
                    }
                    next;
                }
                else{
                    $at--;
                    decode_error("malformed JSON string, neither array, object, number, string or atom");
                }
            }
            else{
                if ($relaxed and $ch eq '#') { # correctly?
                    pos($text) = $at;
                    $text =~ /\G([^\n]*(?:\r\n|\r|\n|$))/g;
                    $at = pos($text);
                    next_chr;
                    next;
                }

                last;
            }
        }
    }


    sub array {
        my $a  = $_[0] || []; # you can use this code to use another array ref object.

        decode_error('json text or perl structure exceeds maximum nesting level (max_depth set too low?)')
                                                    if (++$depth > $max_depth);

        next_chr();
        white();

        if(defined $ch and $ch eq ']'){
            --$depth;
            next_chr();
            return $a;
        }
        else {
            while(defined($ch)){
                push @$a, value();

                white();

                if (!defined $ch) {
                    last;
                }

                if($ch eq ']'){
                    --$depth;
                    next_chr();
                    return $a;
                }

                if($ch ne ','){
                    last;
                }

                next_chr();
                white();

                if ($relaxed and $ch eq ']') {
                    --$depth;
                    next_chr();
                    return $a;
                }

            }
        }

        decode_error(", or ] expected while parsing array");
    }


    sub object {
        my $o = $_[0] || {}; # you can use this code to use another hash ref object.
        my $k;

        decode_error('json text or perl structure exceeds maximum nesting level (max_depth set too low?)')
                                                if (++$depth > $max_depth);
        next_chr();
        white();

        if(defined $ch and $ch eq '}'){
            --$depth;
            next_chr();
            if ($F_HOOK) {
                return _json_object_hook($o);
            }
            return $o;
        }
        else {
            while (defined $ch) {
                $k = ($allow_barekey and $ch ne '"' and $ch ne "'") ? bareKey() : string();
                white();

                if(!defined $ch or $ch ne ':'){
                    $at--;
                    decode_error("':' expected");
                }

                next_chr();
                $o->{$k} = value();
                white();

                last if (!defined $ch);

                if($ch eq '}'){
                    --$depth;
                    next_chr();
                    if ($F_HOOK) {
                        return _json_object_hook($o);
                    }
                    return $o;
                }

                if($ch ne ','){
                    last;
                }

                next_chr();
                white();

                if ($relaxed and $ch eq '}') {
                    --$depth;
                    next_chr();
                    if ($F_HOOK) {
                        return _json_object_hook($o);
                    }
                    return $o;
                }

            }

        }

        $at--;
        decode_error(", or } expected while parsing object/hash");
    }


    sub bareKey { # doesn't strictly follow Standard ECMA-262 3rd Edition
        my $key;
        while($ch =~ /[^\x00-\x23\x25-\x2F\x3A-\x40\x5B-\x5E\x60\x7B-\x7F]/){
            $key .= $ch;
            next_chr();
        }
        return $key;
    }


    sub word {
        my $word =  substr($text,$at-1,4);

        if($word eq 'true'){
            $at += 3;
            next_chr;
            return $Test::ModuleVersion::JSON::PP::true;
        }
        elsif($word eq 'null'){
            $at += 3;
            next_chr;
            return undef;
        }
        elsif($word eq 'fals'){
            $at += 3;
            if(substr($text,$at,1) eq 'e'){
                $at++;
                next_chr;
                return $Test::ModuleVersion::JSON::PP::false;
            }
        }

        $at--; # for decode_error report

        decode_error("'null' expected")  if ($word =~ /^n/);
        decode_error("'true' expected")  if ($word =~ /^t/);
        decode_error("'false' expected") if ($word =~ /^f/);
        decode_error("malformed JSON string, neither array, object, number, string or atom");
    }


    sub number {
        my $n    = '';
        my $v;

        # According to RFC4627, hex or oct digts are invalid.
        if($ch eq '0'){
            my $peek = substr($text,$at,1);
            my $hex  = $peek =~ /[xX]/; # 0 or 1

            if($hex){
                decode_error("malformed number (leading zero must not be followed by another digit)");
                ($n) = ( substr($text, $at+1) =~ /^([0-9a-fA-F]+)/);
            }
            else{ # oct
                ($n) = ( substr($text, $at) =~ /^([0-7]+)/);
                if (defined $n and length $n > 1) {
                    decode_error("malformed number (leading zero must not be followed by another digit)");
                }
            }

            if(defined $n and length($n)){
                if (!$hex and length($n) == 1) {
                   decode_error("malformed number (leading zero must not be followed by another digit)");
                }
                $at += length($n) + $hex;
                next_chr;
                return $hex ? hex($n) : oct($n);
            }
        }

        if($ch eq '-'){
            $n = '-';
            next_chr;
            if (!defined $ch or $ch !~ /\d/) {
                decode_error("malformed number (no digits after initial minus)");
            }
        }

        while(defined $ch and $ch =~ /\d/){
            $n .= $ch;
            next_chr;
        }

        if(defined $ch and $ch eq '.'){
            $n .= '.';

            next_chr;
            if (!defined $ch or $ch !~ /\d/) {
                decode_error("malformed number (no digits after decimal point)");
            }
            else {
                $n .= $ch;
            }

            while(defined(next_chr) and $ch =~ /\d/){
                $n .= $ch;
            }
        }

        if(defined $ch and ($ch eq 'e' or $ch eq 'E')){
            $n .= $ch;
            next_chr;

            if(defined($ch) and ($ch eq '+' or $ch eq '-')){
                $n .= $ch;
                next_chr;
                if (!defined $ch or $ch =~ /\D/) {
                    decode_error("malformed number (no digits after exp sign)");
                }
                $n .= $ch;
            }
            elsif(defined($ch) and $ch =~ /\d/){
                $n .= $ch;
            }
            else {
                decode_error("malformed number (no digits after exp sign)");
            }

            while(defined(next_chr) and $ch =~ /\d/){
                $n .= $ch;
            }

        }

        $v .= $n;

        if ($v !~ /[.eE]/ and length $v > $max_intsize) {
            if ($allow_bigint) { # from Adam Sussman
                require Math::BigInt;
                return Math::BigInt->new($v);
            }
            else {
                return "$v";
            }
        }
        elsif ($allow_bigint) {
            require Math::BigFloat;
            return Math::BigFloat->new($v);
        }

        return 0+$v;
    }


    sub is_valid_utf8 {

        $utf8_len = $_[0] =~ /[\x00-\x7F]/  ? 1
                  : $_[0] =~ /[\xC2-\xDF]/  ? 2
                  : $_[0] =~ /[\xE0-\xEF]/  ? 3
                  : $_[0] =~ /[\xF0-\xF4]/  ? 4
                  : 0
                  ;

        return unless $utf8_len;

        my $is_valid_utf8 = substr($text, $at - 1, $utf8_len);

        return ( $is_valid_utf8 =~ /^(?:
             [\x00-\x7F]
            |[\xC2-\xDF][\x80-\xBF]
            |[\xE0][\xA0-\xBF][\x80-\xBF]
            |[\xE1-\xEC][\x80-\xBF][\x80-\xBF]
            |[\xED][\x80-\x9F][\x80-\xBF]
            |[\xEE-\xEF][\x80-\xBF][\x80-\xBF]
            |[\xF0][\x90-\xBF][\x80-\xBF][\x80-\xBF]
            |[\xF1-\xF3][\x80-\xBF][\x80-\xBF][\x80-\xBF]
            |[\xF4][\x80-\x8F][\x80-\xBF][\x80-\xBF]
        )$/x )  ? $is_valid_utf8 : '';
    }


    sub decode_error {
        my $error  = shift;
        my $no_rep = shift;
        my $str    = defined $text ? substr($text, $at) : '';
        my $mess   = '';
        my $type   = $] >= 5.008           ? 'U*'
                   : $] <  5.006           ? 'C*'
                   : utf8::is_utf8( $str ) ? 'U*' # 5.6
                   : 'C*'
                   ;

        for my $c ( unpack( $type, $str ) ) { # emulate pv_uni_display() ?
            $mess .=  $c == 0x07 ? '\a'
                    : $c == 0x09 ? '\t'
                    : $c == 0x0a ? '\n'
                    : $c == 0x0d ? '\r'
                    : $c == 0x0c ? '\f'
                    : $c <  0x20 ? sprintf('\x{%x}', $c)
                    : $c == 0x5c ? '\\\\'
                    : $c <  0x80 ? chr($c)
                    : sprintf('\x{%x}', $c)
                    ;
            if ( length $mess >= 20 ) {
                $mess .= '...';
                last;
            }
        }

        unless ( length $mess ) {
            $mess = '(end of string)';
        }

        Carp::croak (
            $no_rep ? "$error" : "$error, at character offset $at (before \"$mess\")"
        );

    }


    sub _json_object_hook {
        my $o    = $_[0];
        my @ks = keys %{$o};

        if ( $cb_sk_object and @ks == 1 and exists $cb_sk_object->{ $ks[0] } and ref $cb_sk_object->{ $ks[0] } ) {
            my @val = $cb_sk_object->{ $ks[0] }->( $o->{$ks[0]} );
            if (@val == 1) {
                return $val[0];
            }
        }

        my @val = $cb_object->($o) if ($cb_object);
        if (@val == 0 or @val > 1) {
            return $o;
        }
        else {
            return $val[0];
        }
    }


    sub PP_decode_box {
        {
            text    => $text,
            at      => $at,
            ch      => $ch,
            len     => $len,
            depth   => $depth,
            encoding      => $encoding,
            is_valid_utf8 => $is_valid_utf8,
        };
    }

} # PARSE


sub _decode_surrogates { # from perlunicode
    my $uni = 0x10000 + (hex($_[0]) - 0xD800) * 0x400 + (hex($_[1]) - 0xDC00);
    my $un  = pack('U*', $uni);
    utf8::encode( $un );
    return $un;
}


sub _decode_unicode {
    my $un = pack('U', hex shift);
    utf8::encode( $un );
    return $un;
}

#
# Setup for various Perl versions (the code from Test::ModuleVersion::JSON::PP58)
#

BEGIN {

    unless ( defined &utf8::is_utf8 ) {
       require Encode;
       *utf8::is_utf8 = *Encode::is_utf8;
    }

    if ( $] >= 5.008 ) {
        *Test::ModuleVersion::JSON::PP::JSON_PP_encode_ascii      = \&_encode_ascii;
        *Test::ModuleVersion::JSON::PP::JSON_PP_encode_latin1     = \&_encode_latin1;
        *Test::ModuleVersion::JSON::PP::JSON_PP_decode_surrogates = \&_decode_surrogates;
        *Test::ModuleVersion::JSON::PP::JSON_PP_decode_unicode    = \&_decode_unicode;
    }

    if ($] >= 5.008 and $] < 5.008003) { # join() in 5.8.0 - 5.8.2 is broken.
        package Test::ModuleVersion::JSON::PP;
        require subs;
        subs->import('join');
        eval q|
            sub join {
                return '' if (@_ < 2);
                my $j   = shift;
                my $str = shift;
                for (@_) { $str .= $j . $_; }
                return $str;
            }
        |;
    }


    sub Test::ModuleVersion::JSON::PP::incr_parse {
        local $Carp::CarpLevel = 1;
        ( $_[0]->{_incr_parser} ||= Test::ModuleVersion::JSON::PP::IncrParser->new )->incr_parse( @_ );
    }


    sub Test::ModuleVersion::JSON::PP::incr_skip {
        ( $_[0]->{_incr_parser} ||= Test::ModuleVersion::JSON::PP::IncrParser->new )->incr_skip;
    }


    sub Test::ModuleVersion::JSON::PP::incr_reset {
        ( $_[0]->{_incr_parser} ||= Test::ModuleVersion::JSON::PP::IncrParser->new )->incr_reset;
    }

    eval q{
        sub Test::ModuleVersion::JSON::PP::incr_text : lvalue {
            $_[0]->{_incr_parser} ||= Test::ModuleVersion::JSON::PP::IncrParser->new;

            if ( $_[0]->{_incr_parser}->{incr_parsing} ) {
                Carp::croak("incr_text can not be called when the incremental parser already started parsing");
            }
            $_[0]->{_incr_parser}->{incr_text};
        }
    } if ( $] >= 5.006 );

} # Setup for various Perl versions (the code from Test::ModuleVersion::JSON::PP58)


###############################
# Utilities
#

BEGIN {
    eval 'require Scalar::Util';
    unless($@){
        *Test::ModuleVersion::JSON::PP::blessed = \&Scalar::Util::blessed;
        *Test::ModuleVersion::JSON::PP::reftype = \&Scalar::Util::reftype;
        *Test::ModuleVersion::JSON::PP::refaddr = \&Scalar::Util::refaddr;
    }
    else{ # This code is from Sclar::Util.
        # warn $@;
        eval 'sub UNIVERSAL::a_sub_not_likely_to_be_here { ref($_[0]) }';
        *Test::ModuleVersion::JSON::PP::blessed = sub {
            local($@, $SIG{__DIE__}, $SIG{__WARN__});
            ref($_[0]) ? eval { $_[0]->a_sub_not_likely_to_be_here } : undef;
        };
        my %tmap = qw(
            B::NULL   SCALAR
            B::HV     HASH
            B::AV     ARRAY
            B::CV     CODE
            B::IO     IO
            B::GV     GLOB
            B::REGEXP REGEXP
        );
        *Test::ModuleVersion::JSON::PP::reftype = sub {
            my $r = shift;

            return undef unless length(ref($r));

            my $t = ref(B::svref_2object($r));

            return
                exists $tmap{$t} ? $tmap{$t}
              : length(ref($$r)) ? 'REF'
              :                    'SCALAR';
        };
        *Test::ModuleVersion::JSON::PP::refaddr = sub {
          return undef unless length(ref($_[0]));

          my $addr;
          if(defined(my $pkg = blessed($_[0]))) {
            $addr .= bless $_[0], 'Scalar::Util::Fake';
            bless $_[0], $pkg;
          }
          else {
            $addr .= $_[0]
          }

          $addr =~ /0x(\w+)/;
          local $^W;
          #no warnings 'portable';
          hex($1);
        }
    }
}


# shamely copied and modified from JSON::XS code.

$Test::ModuleVersion::JSON::PP::true  = do { bless \(my $dummy = 1), "Test::ModuleVersion::JSON::PP::Boolean" };
$Test::ModuleVersion::JSON::PP::false = do { bless \(my $dummy = 0), "Test::ModuleVersion::JSON::PP::Boolean" };

sub is_bool { defined $_[0] and UNIVERSAL::isa($_[0], "Test::ModuleVersion::JSON::PP::Boolean"); }

sub true  { $Test::ModuleVersion::JSON::PP::true  }
sub false { $Test::ModuleVersion::JSON::PP::false }
sub null  { undef; }

###############################

package Test::ModuleVersion::JSON::PP::Boolean;

use overload (
   "0+"     => sub { ${$_[0]} },
   "++"     => sub { $_[0] = ${$_[0]} + 1 },
   "--"     => sub { $_[0] = ${$_[0]} - 1 },
   fallback => 1,
);


###############################

package Test::ModuleVersion::JSON::PP::IncrParser;

use strict;

use constant INCR_M_WS   => 0; # initial whitespace skipping
use constant INCR_M_STR  => 1; # inside string
use constant INCR_M_BS   => 2; # inside backslash
use constant INCR_M_JSON => 3; # outside anything, count nesting
use constant INCR_M_C0   => 4;
use constant INCR_M_C1   => 5;

$Test::ModuleVersion::JSON::PP::IncrParser::VERSION = '1.01';

my $unpack_format = $] < 5.006 ? 'C*' : 'U*';

sub new {
    my ( $class ) = @_;

    bless {
        incr_nest    => 0,
        incr_text    => undef,
        incr_parsing => 0,
        incr_p       => 0,
    }, $class;
}


sub incr_parse {
    my ( $self, $coder, $text ) = @_;

    $self->{incr_text} = '' unless ( defined $self->{incr_text} );

    if ( defined $text ) {
        if ( utf8::is_utf8( $text ) and !utf8::is_utf8( $self->{incr_text} ) ) {
            utf8::upgrade( $self->{incr_text} ) ;
            utf8::decode( $self->{incr_text} ) ;
        }
        $self->{incr_text} .= $text;
    }


    my $max_size = $coder->get_max_size;

    if ( defined wantarray ) {

        $self->{incr_mode} = INCR_M_WS unless defined $self->{incr_mode};

        if ( wantarray ) {
            my @ret;

            $self->{incr_parsing} = 1;

            do {
                push @ret, $self->_incr_parse( $coder, $self->{incr_text} );

                unless ( !$self->{incr_nest} and $self->{incr_mode} == INCR_M_JSON ) {
                    $self->{incr_mode} = INCR_M_WS if $self->{incr_mode} != INCR_M_STR;
                }

            } until ( length $self->{incr_text} >= $self->{incr_p} );

            $self->{incr_parsing} = 0;

            return @ret;
        }
        else { # in scalar context
            $self->{incr_parsing} = 1;
            my $obj = $self->_incr_parse( $coder, $self->{incr_text} );
            $self->{incr_parsing} = 0 if defined $obj; # pointed by Martin J. Evans
            return $obj ? $obj : undef; # $obj is an empty string, parsing was completed.
        }

    }

}


sub _incr_parse {
    my ( $self, $coder, $text, $skip ) = @_;
    my $p = $self->{incr_p};
    my $restore = $p;

    my @obj;
    my $len = length $text;

    if ( $self->{incr_mode} == INCR_M_WS ) {
        while ( $len > $p ) {
            my $s = substr( $text, $p, 1 );
            $p++ and next if ( 0x20 >= unpack($unpack_format, $s) );
            $self->{incr_mode} = INCR_M_JSON;
            last;
       }
    }

    while ( $len > $p ) {
        my $s = substr( $text, $p++, 1 );

        if ( $s eq '"' ) {
            if (substr( $text, $p - 2, 1 ) eq '\\' ) {
                next;
            }

            if ( $self->{incr_mode} != INCR_M_STR  ) {
                $self->{incr_mode} = INCR_M_STR;
            }
            else {
                $self->{incr_mode} = INCR_M_JSON;
                unless ( $self->{incr_nest} ) {
                    last;
                }
            }
        }

        if ( $self->{incr_mode} == INCR_M_JSON ) {

            if ( $s eq '[' or $s eq '{' ) {
                if ( ++$self->{incr_nest} > $coder->get_max_depth ) {
                    Carp::croak('json text or perl structure exceeds maximum nesting level (max_depth set too low?)');
                }
            }
            elsif ( $s eq ']' or $s eq '}' ) {
                last if ( --$self->{incr_nest} <= 0 );
            }
            elsif ( $s eq '#' ) {
                while ( $len > $p ) {
                    last if substr( $text, $p++, 1 ) eq "\n";
                }
            }

        }

    }

    $self->{incr_p} = $p;

    return if ( $self->{incr_mode} == INCR_M_STR and not $self->{incr_nest} );
    return if ( $self->{incr_mode} == INCR_M_JSON and $self->{incr_nest} > 0 );

    return '' unless ( length substr( $self->{incr_text}, 0, $p ) );

    local $Carp::CarpLevel = 2;

    $self->{incr_p} = $restore;
    $self->{incr_c} = $p;

    my ( $obj, $tail ) = $coder->PP_decode_json( substr( $self->{incr_text}, 0, $p ), 0x10000001 );

    $self->{incr_text} = substr( $self->{incr_text}, $p );
    $self->{incr_p} = 0;

    return $obj or '';
}


sub incr_text {
    if ( $_[0]->{incr_parsing} ) {
        Carp::croak("incr_text can not be called when the incremental parser already started parsing");
    }
    $_[0]->{incr_text};
}


sub incr_skip {
    my $self  = shift;
    $self->{incr_text} = substr( $self->{incr_text}, $self->{incr_c} );
    $self->{incr_p} = 0;
}


sub incr_reset {
    my $self = shift;
    $self->{incr_text}    = undef;
    $self->{incr_p}       = 0;
    $self->{incr_mode}    = 0;
    $self->{incr_nest}    = 0;
    $self->{incr_parsing} = 0;
}

package
  Test::ModuleVersion::ModuleURL;
our @ISA = ('Test::ModuleVersion::Object::Simple');
use strict;
use warnings;
sub has { __PACKAGE__->Test::ModuleVersion::Object::Simple::attr(@_) }

has distnames => sub { {} };
has privates => sub { {} };
has 'error';
has lwp => 'auto';

sub get {
  my ($self, $module, $version, $opts) = @_;
  
  $opts ||= {};
  my $distnames = $self->distnames;
  my $privates = $self->privates;
  my $lwp = $self->lwp;

  # Module
  my $module_dist = $module;
  $module_dist = $distnames->{$module} if defined $distnames->{$module};
  $module_dist =~ s/::/-/g;
  
  my $url;
  if ($url = $privates->{$module}) {
    $url =~ s/%M/"$module_dist-$version"/e;
  }
  else {
    
    # Get dounload URL using metaCPAN api
    my $metacpan_api = 'http://api.metacpan.org/v0';
    my $search = "release/_search?q=name:$module_dist-$version"
      . "&fields=download_url,name";
    my $module_info = "$metacpan_api/$search";
    my $res = {};
    my $agent;
    if ($lwp eq 'use' || $lwp eq 'auto' && eval { require LWP::UserAgent; LWP::UserAgent->VERSION(5.802) })
    {
      require LWP::UserAgent;
      $agent = 'LWP::UserAgent';
      my $ua = LWP::UserAgent->new(
        parse_head => 0,
        env_proxy => 1,
        agent => "Test::ModuleVersion/$VERSION",
        timeout => 30
      );
      my $r = $ua->get($module_info);
      $agent = 'LWP::UserAgent';
      $res->{success} = $r->is_success;
      $res->{status_line} = $r->status_line;
      $res->{content} = $r->content;
    }
    else {
      $agent = 'HTTP::Tiny';
      my $ua = Test::ModuleVersion::HTTP::Tiny->new;
      my $r = $ua->get($module_info);
      $res->{success} = $r->{success};
      $res->{status_line} = "$r->{status} $r->{reason}";
      $res->{content} = $r->{content};
    }
    
    my $error;
    if ($res->{success} && !$ENV{TEST_MODULEVERSION_REQUEST_FAIL}) {
      my $release = Test::ModuleVersion::JSON::PP::decode_json $res->{content};
      $url = $release->{hits}{hits}[0]{fields}{download_url};
      $error = "$module_dist-$version is unknown" unless defined $url;
    }
    else {
      $error = "Request to metaCPAN fail($res->{status_line}):$agent:$module_info";
    }
    $self->error($error);
  }
  
  return $url;
}


package Test::ModuleVersion;
our @ISA = ('Test::ModuleVersion::Object::Simple');
use strict;
use warnings;
use ExtUtils::Installed;
use Carp 'croak';
use Data::Dumper;

sub has { __PACKAGE__->Test::ModuleVersion::Object::Simple::attr(@_) }
has before => '';
has distnames => sub { {} };
has default_ignore => sub { ['Perl', 'Test::ModuleVersion'] };
has lib => sub { [] };
has modules => sub { [] };
has privates => sub { {} };

sub detect {
  my ($self, %opts) = @_;
  my $ignore = $opts{ignore} || [];
  
  # Detect installed modules
  my $ei = ExtUtils::Installed->new;
  my @modules;
  for my $module (sort $ei->modules) {
    next if grep { $module eq $_ } @$ignore;
    eval "require $module";
    no strict 'refs';
    my $version = ${"${module}::VERSION"};
    push @modules, [$module => $version] if length $version;
  }

  return \@modules;
}

sub test_script {
  my ($self, %opts) = @_;
  
  # Code
  my $code;

  # Library path
  my $libs = ref $self->lib ? $self->lib : [$self->lib];
  $code .= "use FindBin;\n";
  $code .= qq|use lib "\$FindBin::Bin/$_";\n| for @$libs;
  
  # Before
  $code .= $self->before . "\n";
  
  # Reffer this module
  $code .= "# Created by Test::ModuleVersion $Test::ModuleVersion::VERSION\n";

  # Test code
  $code .= <<'EOS';
use Test::More;
use strict;
use warnings;
use ExtUtils::Installed;
EOS
  
  # Main
  $code .= <<'EOS';

sub main {
  my $command = shift;
  my @options = @_;
  
  die qq/command "$command" is unkonwn command/
    if defined $command && $command ne 'list';
  
  my $list_failed;
  my $lwp = 'auto';
  for my $option (@options) {
    if ($option eq '--fail') { $list_failed = 1 }
    elsif ($option eq '--lwp') { $lwp = 'use' }
    elsif ($option eq '--no-lwp') { $lwp = 'no' }
    else { die qq/list $option is unknown option/ }
  }
  
  if (defined $command) {
    my $builder = Test::More->builder;
    open my $out_fh, '>', undef;
    $builder->output($out_fh);
    $builder->failure_output($out_fh);
    $builder->todo_output($out_fh);
  }

  my $modules = [];
  my $failed = [];
  my $require_ok;
  my $version_ok;
  my $version;
  
  plan tests => <%%%%%% test_count %%%%%%>;

EOS
  
  # Module and version check
  my $test_count = 0;
  for my $m (@{$self->modules}) {
    my ($module, $version) = @$m;
    $code .= "  # $module\n"
      . "  \$require_ok = require_ok('$module');\n"
      . "  \$version_ok = is(\$${module}::VERSION, '$version', '$module version: $version');\n"
      . "  push \@\$modules, ['$module' => '$version'];\n"
      . "  push \@\$failed, ['$module' => '$version'] unless \$require_ok && \$version_ok;\n\n";
    $test_count += 2;
  }
  
  # Print module URLs
  $code .= <<'EOS';
  # Print module URLs
  if (defined $command) {
    my $distnames = <%%%%%% distnames %%%%%%>
    ;
    my $privates = <%%%%%% privates %%%%%%>
    ;
    my $tm = Test::ModuleVersion->new;
    my @ms = $command eq 'list' && $list_failed ? @$failed
      : $command eq 'list' ? @$modules
      : [];
    for my $m (@ms) {
      my ($module, $version) = @$m;
      my $mu = Test::ModuleVersion::ModuleURL->new;
      $mu->distnames($distnames);
      $mu->privates($privates);
      $mu->lwp($lwp);
      my $url = $mu->get($module, $version);
      if (defined $url) { print "$url\n" }
      else { print STDERR $mu->error . "\n" }
    }  
  }
}

EOS
  
  # Embbed Test::ModuleVersion
  $code .= $self->_source . "\n";
  
  # Run
  $code .= "package main;\n"
    . "main(\@ARGV);\n";
  
  # Test count
  $code =~ s/<%%%%%% test_count %%%%%%>/$test_count/e;
  
  # Distribution names
  my $distnames_code = Data::Dumper->new([$self->distnames])->Terse(1)->Indent(2)->Dump;
  $code =~ s/<%%%%%% distnames %%%%%%>/$distnames_code/e;

  # Private repositories
  my $privates_code = Data::Dumper->new([$self->privates])->Terse(1)->Indent(2)->Dump;
  $code =~ s/<%%%%%% privates %%%%%%>/$privates_code/e;
  
  if (my $file = $opts{output}) {
    open my $fh, '>', $file
      or die qq/Can't open file "$file": $!/;
    print $fh $code;
  }
  return $code;
}

sub _source {
  my $self = shift;
  
  # Source
  my $class = __PACKAGE__;
  $class =~ s/::/\//g;
  $class .= '.pm';
  my $path = $INC{$class};
  open my $fh, '<', $path
    or croak qq/Can't open "$path": $!/;
  my $source;
  while (my $line = <$fh>) {
    last if $line =~ /^=head1/;
    $source .= $line;
  }
  return $source;
}

1;


package main;
main(@ARGV);
