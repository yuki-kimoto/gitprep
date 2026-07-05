package Gitprep::Mail;
use Mojo::Base -base;

use strict;
use warnings;

use Net::Curl::Easy qw(:constants);


has 'app';

my $conf;


sub can_send {
  my $self = shift;
  return $conf->{send} && $self->app->{site_url};
}

sub sendmail_job {
  my ($self, $mime, $to, %options) = @_;
  my @command = ($conf->{sendmail}, "-f$conf->{from}");
  push @command, $_ for (@$to);
  my $job = $self->app->jobs->command(\@command,
    stdin => \$mime,
    %options
  );
  return $job;
}

sub smtp_job {
  my ($self, $mime, $to, %options) = @_;

  return $self->app->jobs->curl(
    'CURLOPT_MAIL_RCPT' => $to,
    stdin => \$mime,
    %options
  );
}

sub configure {
  my ($self, $config) = @_;
  my $from = $config->{mail}{from};
  $conf = {};
  if (defined $from) {
    $conf->{from} = $config->{mail}{from} if defined $config->{mail}{from};
    if (defined $config->{smtp}{hosts}) {
      $conf->{send} = \&smtp_job;
      $conf->{'CURLOPT_MAIL_FROM'} = $from;
      $conf->{'CURLOPT_UPLOAD'} = 1;
      $conf->{'CURLOPT_SASL_IR'} = 1;
      my $smtp = $config->{smtp};
      my %map_field = (
        sasl_username     => 'CURLOPT_USERNAME',
        sasl_password     => 'CURLOPT_PASSWORD',
        login_options     => 'CURLOPT_LOGIN_OPTIONS',
        SSL_ca_file       => 'CURLOPT_CAINFO',
        SSL_ca_path       => 'CURLOPT_CAPATH',
        SSL_cert_file     => 'CURLOPT_SSLCERT',
        SSL_key_file      => 'CURLOPT_SSLKEY',
        SSL_cipher_list   => 'CURLOPT_SSL_CIPHER_LIST',
        SSL_ciphersuites  => 'CURLOPT_TLS13_CIPHERS',
        SSL_crl_file      => 'CURLOPT_CRLFILE'
      );
      for (keys %$smtp) {
        $conf->{$map_field{$_}} = $smtp->{$_} if exists $map_field{$_};
      }
      my $vrfy = $smtp->{SSL_verify_mode} // 'SSL_VERIFY_PEER SSL_VERIFY_HOST';
      $conf->{'CURLOPT_SSL_VERIFYPEER'} = $vrfy =~ /\bSSL_VERIFY_PEER\b/? 1: 0;
      $conf->{'CURLOPT_SSL_VERIFYHOST'} = $vrfy =~ /\bSSL_VERIFY_HOST\b/? 1: 0;
      my $url = 'smtp';
      if (defined $smtp->{ssl}) {
        if ($smtp->{ssl} eq 'ssl') {
          $url .= 's';
        }
        else {
          $conf->{'CURLOPT_USE_SSL'} = CURLUSESSL_ALL;
        }
      }

      $url .= '://' . (split /\s+/, $smtp->{hosts})[0];
      $url .= ":$smtp->{port}" if exists $smtp->{port};
      $conf->{'CURLOPT_URL'} = $url;
    }
    else {
      $conf->{from} = $from;
      my $sendmail = $config->{sendmail}{sendmail};
      unless (defined $sendmail) {
        my @path;
        @path = split ':', $ENV{PATH} if exists $ENV{PATH};
        for my $p (@path, '/usr/sbin', '/usr/lib') {
          $p =~ s/^\s*(.*?)\s*$/$1/;
          $p = '.' if $p eq '';
          $p .= '/sendmail';
          if (-x $p) {
            $sendmail = $p;
            last;
          }
        }
      }
      if (defined $sendmail) {
        $conf->{sendmail} = $sendmail;
        $conf->{send} = \&sendmail_job;
      }
    }
  }
}


sub mail_job {
  my ($self, $mime, $to) = (shift, shift, shift);
  return unless $self->can_send;
  my %options = (
    %$conf,
    @_
  );
  return $conf->{send}->($self, $mime, $to, %options);
}

sub queue_mail {
  my $self = shift;
  my $job = $self->mail_job(@_);
  $self->app->jobs->enqueue($job) if defined $job;
}

1;
