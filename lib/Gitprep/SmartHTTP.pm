package Gitprep::SmartHTTP;

use Mojo::Base -base;

use File::Spec::Functions;
use Symbol qw(gensym);
use IPC::Open3;
use IO::Select;
use IO::Uncompress::Gunzip qw($GunzipError);

use constant BUFFER_SIZE => 8192;

has buffer_size => 8192;

our $VERSION = '0.05';
my @SERVICES = (
  [ 'POST', 'service_rpc', qr{(.*?)/git-upload-pack$},  'upload-pack' ],
  [ 'POST', 'service_rpc', qr{(.*?)/git-receive-pack$}, 'receive-pack' ],
);

sub service_rpc {
    my $self = shift;
    my $args = shift;

    my $req = $args->{req};
    my $rpc = $args->{rpc};

    return $self->return_403
      unless $self->has_access( $req, $rpc, 1 );

    my @cmd = $self->git_command( $rpc, '--stateless-rpc', '.' );

    my $input = $req->input;
    if ( exists $req->env->{HTTP_CONTENT_ENCODING}
        && $req->env->{HTTP_CONTENT_ENCODING} =~ /^(?:x-)?gzip$/ )
    {
        $input = IO::Uncompress::Gunzip->new($input);
        unless ($input) {
            $req->env->{'psgi.errors'}->print("gunzip failed: $GunzipError");
            return $self->return_400;
        }
    }
    my ( $cout, $cerr ) = ( gensym, gensym );
    my $pid = open3( my $cin, $cout, $cerr, @cmd );
    my $input_len = 0;
    while ( my $len = $input->read( my $buf, BUFFER_SIZE ) > 0 ) {
        print $cin $buf;
        $input_len += $len;
    }
    close $cin;
    if ( $input_len == 0 ) {
        close $cout;
        close $cerr;
        waitpid( $pid, 0 );
        return $self->return_400;
    }

    return sub {
        my $respond = shift;
        my $writer  = $respond->(
            [
                200,
                [
                    'Content-Type' =>
                      sprintf( 'application/x-git-%s-result', $rpc ),
                ]
            ]
        );

        my ( $out, $err, $buf ) = ( '', '', '' );
        my $s = IO::Select->new( $cout, $cerr );
        while ( my @ready = $s->can_read ) {
            for my $handle (@ready) {
                while ( sysread( $handle, $buf, BUFFER_SIZE ) ) {
                    if ( $handle == $cerr ) {
                        $err .= $buf;
                    }
                    else {
                        $writer->write($buf);
                    }
                }
                $s->remove($handle) if eof($handle);
            }
        }
        close $cout;
        close $cerr;
        waitpid( $pid, 0 );

        if ($err) {
            $req->env->{'psgi.errors'}->print("git command failed: $err");
        }
        $writer->close();
      }
}

1;
