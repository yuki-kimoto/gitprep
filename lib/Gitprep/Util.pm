package Gitprep::Util;

use strict;
use warnings;
use IPC::Open3 ();
use Scalar::Util qw(openhandle);
use Symbol qw(gensym);
use Errno qw(EINTR);
use POSIX qw(:sys_wait_h);
use File::Spec;
use MIME::Base64;
use Crypt::Digest::SHA256 qw(sha256);

# Interface to IPC::Open3.
#
# Mandatory argument:
#  cmd          An array containg the command and its parameters.
# Optional keyword arguments:
#  stdin        Standard input disposition (see below).
#  stdout       Standard output disposition.
#  stderr       Error output disposition.
#  environ      Child proocess environment.
#
# Standard file descriptor disposition can be specified as:
#  a currently open file handle,
#  an open system file descriptor,
#  '|' to request an interprocess pipe,
#  '&' to use the corresponding global file handle.
#  '-' to close the file descriptor.
# In addition, stderr can be specified as '>' to redirect it to stdout.
# Everything else is interpreted by Open3. Default is to open the file
#  descriptor on /dev/null.
#
# Returns a structure with members:
#  pid          The sub-process pid.
#  stdin        The output pipe handle feeding the sub-process input, if some.
#  stdout       The input pipe handle to read the sub-process output, if some.
#  stderr       The input pipe handle to read the sub-process errors, if some.
sub command {
  my ($cmd, %options) = @_;
  my $null;
  my @to_close;
  my $child = {};

  # Translate our disposition syntax into the Open3 equivalent.
  my $setup_disposition = sub {
    my ($id, $globfh) = @_;
    my $option = $options{$id};
    if (!defined $option) {
      open $null, '+<', '/dev/null' unless defined $null;
      return fileno $null;
    }
    $option = $globfh if $option eq '&';
    if (openhandle($option)) {
      $option->flush;
      return ['&', $option];
    }
    if ($option eq '-') {
      # Open3 does not support exec'ing a program with a standard file
      #  descriptor closed. So establish a pipe that will be immediately closed
      #  on parent side.
      push @to_close, $id;
      return gensym;
    }
    return gensym if $option eq '|';
    return 0 + $option if $option =~ /^0|[1-9]\d*$/;
    return undef if $option eq '>';
    return $option;
  };

  my $ih = $setup_disposition->('stdin', \*STDIN);
  my $oh = $setup_disposition->('stdout', \*STDOUT);
  my $eh = $setup_disposition->('stderr', \*STDERR);
  my $pid = -1;

  eval {
    local %ENV;
    %ENV = %{$options{environ}} if exists $options{environ};
    $pid = IPC::Open3::open3($ih, $oh, $eh, @{$cmd});
  };

  close($null) if $null;

  if ($pid < 0) {
    $child->{error} = $@;
  } else {
    $child->{pid} = $pid;
    $child->{stdin} = $ih if openhandle($ih);
    $child->{stdout} = $oh if openhandle($oh);
    $child->{stderr} = $eh if openhandle($eh);
    close_pipe($child, $_) for (@to_close);
  }

  return $child;
}

# Close a child's I/O pipe by name.
sub close_pipe {
  my ($child, $pipe) = @_;
  close $child->{$pipe} if exists $child->{$pipe};
  delete $child->{$pipe};
}

sub close_all {
  my ($child) = @_;
  close_pipe($child, $_) for ('stdin', 'stdout', 'stderr');
}

# Wait for a child process to exit.
#
# Arguments:
#  child        A child process structure as returned by command().
#
# Options:
#  flags        waitpid() flags, default to 0.
#  condition    A subroutine returning a bool telling if the wait is over.
#               It receives the process exit code returned by waitpid() in
#               argument. Default is to continue waiting until the process
#               is really dead.
#
# Upon exit, the child structure can be modified as follows if the process
# died while waiting:
#  pid          deleted.
#  exit_code    the full exit code as retuned by waitpid().
#  exit_status  the exit argument as executed by the process, if pertaining.
#  signal       the signal number that killed the process, if some.
sub wait_for {
  my ($child, %options) = @_;
  my $exit_code = $child->{exit_code};
  my $condition = $options{condition} //= sub { 0 };
  my $flags = $options{flags} // 0;
  while (exists $child->{pid}) {
    $exit_code = $child->{exit_code};
    last if defined $exit_code;
    my $r = waitpid($child->{pid}, $flags);
    last if $r == 0;
    if ($r < 0) {
      next if $! == EINTR;
      $child->{error} = "$!";
    } elsif ($r != $child->{pid}) {
      $child->{error} = "waitpid returned $r instead of $child->{pid}";
    } else {
      $exit_code = $?;
      if (WIFEXITED($exit_code)) {
        $child->{exit_code} = $exit_code;
        $child->{exit_status} = WEXITSTATUS($exit_code);
        delete $child->{pid};
      } elsif (WIFSIGNALED($exit_code)) {
        $child->{exit_code} = $exit_code;
        $child->{signal} = WTERMSIG($exit_code);
        delete $child->{pid};
      } elsif (!$condition->($exit_code)) {
        next;
      }
    }
    last;
  }
  return $exit_code;
}

# Check if a child process is running,
sub child_running {
  my ($child) = @_;
  wait_for($child, flags => WNOHANG);   # Resolve zombie.
  return exists $child->{pid};
}

# Run a command synchronously.
#
# I/O channels are unhandled: closed or ignored.
#
# Returns true if command terminate successfully.
sub run_command {
  my @cmd = @_;

  # Run command (Suppress STDOUT and STDERR).
  my $child = command(\@cmd, stdin => '-');
  wait_for($child);
  return $child->{signal} || $child->{exit_status} ? 0 : 1;
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
