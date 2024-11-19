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


sub glob2regex {
  my ($glob) = @_;

  # Translate a glob pattern into a regular expression.

  my $regex;

  # Translate wildcards '*', '**' and '?'.
  local *wildcard = sub {
    my ($glob) = @_;
    my $regex;
    my $min = 0;
    my $nomax;

    if ($glob =~ /^\*{2,}(.*)$/) {
      $nomax = 1;
      $regex = '.';
      $glob = $1;
    } else {
      $regex = '[^/]';
      # Optimize consecutive wildcards gathering min and max counts.
      while ($glob =~ /^(\?|\*(?!\*))(.*)$/) {
        $min++ if $1 eq '?';
        $nomax = 1 if $1 eq '*';
        $glob = $2;
      }
    }

    # Generate repetition counts.
    $regex .= '*' if !$min;
    $regex .= '+' if $min == 1 && $nomax;
    $regex .= '{' . $min . ($nomax? ',': '') . '}' if $min > 1;
    return ($glob, $regex);
  };

  # Translate [] sets.
  local *set = sub {
    my ($glob) = @_;
    my $regex = '';
    if ($glob =~ /^[\^!](.*)$/) {
      $regex = '^';
      $glob = $1;
    }
    # Convert set content.
    while ($glob =~ /^([^\]]|$)(.*)$/) {
      if ($1 ne '-') {
        $2 =~ /^(.)(.*)$/ if $1 eq '\\' && $2;
        ;
      }
      $regex .= $1;
      $glob = $2;
    }
    return (substr($glob, 1), "[$regex]");
  };

  # Translate {,} groups.
  local *group = sub {
    my ($glob) = @_;
    my $regex;

    while ($glob =~ /^[^}]/) {
      if ($glob =~ /^,+(.*)$/) {
        $glob = $1;
        $regex .= '|';
      } else {
        ($glob, my $term) = terms($glob, 1);
        $regex .= $term;
      }
    }
    return (substr($glob, 1), "(?:$regex)");
  };

  # Translate a sequence of terms.
  local *terms = sub {
    my ($glob, $ingroup) = @_;
    my $regex;
    my $re;

    while ($glob =~ /^(.)(.*)$/) {
      last if $ingroup && $1 =~ /[,}]/;
      if ($1 eq '[') {
        ($glob, $re) = set($2);
      } elsif ($1 eq '{') {
        ($glob, $re) = group($2);
      } elsif ($1 =~ /[?*]/) {
        ($glob, $re) = wildcard($glob);
      } else {
        $2 =~ /^(.)(.*)$/ if $1 eq '\\';
        $glob = $2;
        $re = $1;
        $re =~ s/[\$^+*?.=!|\\()[{}]/\\$&/;
      }
      $regex .= $re;
    }
    return ($glob, $regex);
  };

  while ($glob =~ /./) {
    ($glob, my $re) = terms($glob);
    $regex .= $re;
  }
  return "^$regex\$";
}


1;
