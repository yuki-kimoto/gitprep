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

    [ 'GET', 'get_info_refs',    qr{(.*?)/info/refs$} ],
    [ 'GET', 'get_text_file',    qr{(.*?)/HEAD$} ],
    [ 'GET', 'get_text_file',    qr{(.*?)/objects/info/alternates$} ],
    [ 'GET', 'get_text_file',    qr{(.*?)/objects/info/http-alternates$} ],
    [ 'GET', 'get_info_packs',   qr{(.*?)/objects/info/packs$} ],
    [ 'GET', 'get_loose_object', qr{(.*?)/objects/[0-9a-f]{2}/[0-9a-f]{38}$} ],
    [
        'GET', 'get_pack_file', qr{(.*?)/objects/pack/pack-[0-9a-f]{40}\.pack$}
    ],
    [ 'GET', 'get_idx_file', qr{(.*?)/objects/pack/pack-[0-9a-f]{40}\.idx$} ],
);

sub get_service {
    my $self = shift;
    my $req  = shift;

    my $service = $req->param('service');
    return unless $service;
    return unless substr( $service, 0, 4 ) eq 'git-';
    $service =~ s/git-//g;
    return $service;
}

sub match_routing {
    my $self = shift;
    my $req  = shift;

    my ( $cmd, $path, $file, $rpc );
    for my $s (@SERVICES) {
        my $match = $s->[2];
        if ( $req->path_info =~ /$match/ ) {
            return ('not_allowed') if $s->[0] ne uc( $req->method );
            $cmd  = $s->[1];
            $path = $1;
            $file = $req->path_info;
            $file =~ s|\Q$path/\E||;
            $rpc = $s->[3];
            return ( $cmd, $path, $file, $rpc );
        }
    }
    return ();
}

sub get_git_repo_dir {
    my $self = shift;
    my $path = shift;

    my $root = $self->root || `pwd`;
    chomp $root;
    $path = catdir( $root, $path );
    return $path if ( -d $path );
    return;
}

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

sub get_info_refs {
    my $self = shift;
    my $args = shift;

    my $req     = $args->{req};
    my $service = $self->get_service($req);
    if ( $self->has_access( $args->{req}, $service ) ) {
        my @cmd =
          $self->git_command( $service, '--stateless-rpc', '--advertise-refs',
            '.' );

        my ( $cout, $cerr ) = ( gensym, gensym );
        my $pid = open3( my $cin, $cout, $cerr, @cmd );
        close $cin;
        my ( $refs, $err, $buf ) = ( '', '', '' );
        my $s = IO::Select->new( $cout, $cerr );
        while ( my @ready = $s->can_read ) {
            for my $handle (@ready) {
                while ( sysread( $handle, $buf, BUFFER_SIZE ) ) {
                    if ( $handle == $cerr ) {
                        $err .= $buf;
                    }
                    else {
                        $refs .= $buf;
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
            return $self->return_400;
        }

        my $res = $req->new_response(200);
        $res->headers(
            [
                'Content-Type' =>
                  sprintf( 'application/x-git-%s-advertisement', $service ),
            ]
        );
        my $body =
          pkt_write("# service=git-${service}\n") . pkt_flush() . $refs;
        $res->body($body);
        return $res->finalize;
    }
    else {
        return $self->dumb_info_refs($args);
    }
}

sub dumb_info_refs {
    my $self = shift;
    my $args = shift;
    $self->update_server_info;
    $self->send_file( $args, "text/plain; charset=utf-8" );
}

sub get_info_packs {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "text/plain; charset=utf-8" );
}

sub get_loose_object {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "application/x-git-loose-object" );
}

sub get_pack_file {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "application/x-git-packed-objects" );
}

sub get_idx_file {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "application/x-git-packed-objects-toc" );
}

sub get_text_file {
    my $self = shift;
    my $args = shift;
    $self->send_file( $args, "text/plain" );
}

sub update_server_info {
    my $self = shift;
    system( $self->git_command('update-server-info') );
}

sub git_command {
    my $self     = shift;
    my @commands = @_;
    my $git_bin  = $self->git_path;
    return ( $git_bin, @commands );
}

sub has_access {
    my $self = shift;
    my ( $req, $rpc, $check_content_type ) = @_;

    if (   $check_content_type
        && $req->content_type ne
        sprintf( "application/x-git-%s-request", $rpc ) )
    {
        return;
    }

    return if !$rpc;
    return $self->received_pack if $rpc eq 'receive-pack';
    return $self->upload_pack   if $rpc eq 'upload-pack';
    return;
}

sub send_file {
    my $self = shift;
    my ( $args, $content_type ) = @_;

    my $file = $args->{reqfile};
    return $self->return_404 unless -e $file;

    my @stat = stat $file;
    my $res  = $args->{req}->new_response(200);
    $res->headers(
        [
            'Content-Type'  => $content_type,
            'Last-Modified' => HTTP::Date::time2str( $stat[9] ),
            'Expires'       => 'Fri, 01 Jan 1980 00:00:00 GMT',
            'Pragma'        => 'no-cache',
            'Cache-Control' => 'no-cache, max-age=0, must-revalidate',
        ]
    );

    if ( $stat[7] ) {
        $res->header( 'Content-Length' => $stat[7] );
    }
    open my $fh, "<:raw", $file
      or return $self->return_403;

    Plack::Util::set_io_path( $fh, Cwd::realpath($file) );
    $res->body($fh);
    $res->finalize;
}

sub pkt_flush {
  my $self = shift;
  
  return '0000';
}

sub pkt_write {
  my $self = shift;
  my $str = shift;
  return sprintf( '%04x', length($str) + 4 ) . $str;
}

sub return_not_allowed {
    my $self = shift;
    my $env  = shift;
    if ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.1' ) {
        return [
            405, [ 'Content-Type' => 'text/plain', 'Content-Length' => 18 ],
            ['Method Not Allowed']
        ];
    }
    else {
        return [
            400, [ 'Content-Type' => 'text/plain', 'Content-Length' => 11 ],
            ['Bad Request']
        ];
    }
}

sub return_403 {
    my $self = shift;
    return [
        403, [ 'Content-Type' => 'text/plain', 'Content-Length' => 9 ],
        ['Forbidden']
    ];
}

sub return_400 {
    my $self = shift;
    return [
        400, [ 'Content-Type' => 'text/plain', 'Content-Length' => 11 ],
        ['Bad Request']
    ];
}

sub return_404 {
    my $self = shift;
    return [
        404, [ 'Content-Type' => 'text/plain', 'Content-Length' => 9 ],
        ['Not Found']
    ];
}

1;
__END__

=head1 NAME

  Plack::App::GitSmartHttp - Git Smart HTTP Server PSGI(Plack) Implementation

=head1 SYNOPSIS

  use Plack::App::GitSmartHttp;

  Plack::App::GitSmartHttp->new(
      root          => '/var/git/repos',
      git_path      => '/usr/bin/git',
      upload_pack   => 1,
      received_pack => 1
  )->to_app;

=head1 DESCRIPTION

  Plack::App::GitSmartHttp is Git Smart HTTP Server PSGI(Plack) Implementation.

=head1 AUTHOR

  Ryuzo Yamamoto E<lt>ryuzo.yamamoto@gmail.comE<gt>

=head1 SEE ALSO

  Smart HTTP Transport : <http://progit.org/2010/03/04/smart-http.html>
  Grack : <https://github.com/schacon/grack>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
