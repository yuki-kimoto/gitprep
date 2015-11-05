package Gitprep::Util;

use strict;
use warnings;
use IPC::Open3 ();
use File::Spec;

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

1;
