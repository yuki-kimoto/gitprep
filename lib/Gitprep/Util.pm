package Gitprep::Util;

use strict;
use warnings;
use IPC::Open3 ();
use File::Spec;
use MIME::Base64;
use Crypt::Digest::SHA256 qw(sha256);

sub run_command {
  my @cmd = @_;
  
  # Run command(Suppress STDOUT and STDERR)
  my($wfh, $rfh, $efh);
  my $pid = IPC::Open3::open3($wfh, $rfh, $efh, @cmd);
  close $wfh;
  () = <$rfh>;
  waitpid($pid, 0);
  
  my $child_exit_status = $? >> 8;
  
  return $child_exit_status == 0 ? 1 : 0;
}

sub fingerprint {
  my ($key) = @_;
  $key =~ /^(ssh-rsa|ssh-dss|ecdsa-sha2-nistp25|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) +(\S+)/; 
  my $type = $1;
  my $data = $2;
  if ($type && $data) {
    return (
      $type, 
      encode_base64(sha256(decode_base64($data))) 
    );
  }

  return;
}


1;
