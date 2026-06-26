package Gitprep::Jobs;
use Mojo::Base -base;

use strict;
use warnings;

use Mojo::IOLoop;
use Mojo::Promise;
use Scalar::Util qw(openhandle);
use Gitprep::Fifo;
use Gitprep::Util;
use Net::Curl::Easy qw(:constants);
use Net::Curl::Promiser::Mojo;

has 'app';


# Create a job for detached execution.
# A job is a promise with additional fields.
#
# Mandatory argument:
#  start      a subroutine starting the job. It receives the job itself in
#             argument and is in charge of triggering the job operations.
#             The job operations should end up in resolving or rejecting
#             the job.
# Keyword arguments:
#  success    a subroutine receiving the job in argument and gets called when
#             the job is resolved.
#  failure    a subroutine receiving the job in argument and gets called when
#             the job is rejected.
#  timeout    run timeout in seconds. Defaults to none.
#  args       Stored in job->{args} for use by the above subroutines.
#  ioloop     target io loop, default is main io loop.
sub new_job {
  my ($self, $start) = (shift, shift);
  my %options = (
    success => sub {},
    failure => sub {},
    ioloop => Mojo::IOLoop->singleton,
    (@_)
  );

  my $job = Mojo::Promise->new->ioloop($options{ioloop});
  $job->then($options{success}, sub {$options{failure}->(@_); ()});
  $job->{start} = $start;
  $job->{timeout} = $options{timeout};
  $job->{args} = $options{args};
  return $job;
}

sub run_jobs {
  my $self = shift;

  for my $job (@_) {
    $job->timeout($job->{timeout}, 'Job timeout') if $job->{timeout};
    $job->reject($@) unless eval { $job->{start}->($job); 1 };
  }
}

sub run_blocking_jobs {
  my ($self, @jobs) = @_;

  return [] unless @jobs;

  my $reject_all = sub {
    $_->reject(@_) for (@jobs);
    return \@jobs;
  };

  my $ioloop = $jobs[0]->ioloop;
  return $reject_all->('ioloop already running') if $ioloop->is_running;

  for my $job (@jobs) {
    return $reject_all->('jobs not is same ioloop') if $job->ioloop ne $ioloop;
  }

  $self->run_jobs(@jobs);
  $ioloop->start;
  return $reject_all->('left ioloop');
}

sub subprocess {
  my ($self, $start, @options) = @_;
  return $self->new_job(sub {
    my $job = shift;
    $job->ioloop->subprocess->run_p($start)->then(
      sub {$job->resolve(@_); ()},
      sub {$job->reject(@_); ()}
    );
  }, @options);
}

# Helper subroutine that establishes an ioloop stream for a file handle.
sub _handle2stream {
  my ($self, $handle, $ioloop) = (shift, shift, shift);
  my %events = (
    close => sub {},
    @_
  );
  my $stream = Mojo::IOLoop::Stream->new($handle);
  my $id = $ioloop->stream($stream);

  my $close = $events{close};
  $events{close} = sub {
    $stream->unsubscribe($_ => delete $events{$_}) for (keys %events);
    $ioloop->remove($id);
    $close->($stream);
  };
  $stream->on($_ => $events{$_}) for (keys %events);
  return $stream;
}

# Create a job submitting a system command.
#
# Mandatory argument:
#  cmd          An array containg the command and its parameters.
# Optional keyword arguments:
#  stdin        Standard input disposition (see below).
#  stdout       Standard output disposition.
#  stderr       Error output disposition.
#  environ      Child proocess environment.
#  buffer_size  Maximum data chunk length to use where pertaining.
#               Defaults to 16384.
#
# Standard file descriptor disposition can be specified as:
#  a currently open file handle,
#  an open system file descriptor,
#  '&' to use the corresponding global file handle.
#  '-' to close the file descriptor.
#  A reference to a scalar to be used as data buffer for the file.
#  A subroutine to use as data provider/consumer callback for the file's data.
#    Input callbacks are called with the pipe Mojo::Stream and maximum length
#    in argument and return the input data or '' at EOF. Output callbacks
#    receive the pipe Mojo::Stream and output data as argument and return
#    a non-empty string to signal an error.
# In addition, stderr can be specified as '>' to redirect it to stdout.
# Everything else is interpreted by Gitprep::Util::command(). Default is
# to associate file to /dev/null.
sub command {
  my ($self, $command, %options) = @_;
  $options{buffer_size} ||= 16384;
  my @filekeys = qw(stdin stdout stderr);
  my %cbs;

  # Map functions and scalar references to handles.
  my $setup_io = sub {
    my ($index) = @_;
    delete $options{$index} if '|' eq ($options{$index} // '|');
    if ('SCALAR' eq ref $options{$index}) {
      my $ref = $options{$index};
      my $offset = 0;
      $options{$index} = sub {$$ref .= $_[1]; ()};
      $options{$index} = sub {
        my ($handle, $maxlen) = @_;
        (undef, my $chunk) = unpack("a$offset a$maxlen", $$ref);
        $offset += length $chunk;
        $chunk
      } if $index eq 'stdin';
    }
    if ('CODE' eq ref $options{$index}) {
      $cbs{$index} = $options{$index};
      $options{$index} = '|';
    }
  };
  $setup_io->($_) for (@filekeys);

  my $job = $self->new_job(
    sub {
      my $job = shift;
      my @promises;

      # Start the command.
      my $child = Gitprep::Util::command($command, %options);
      $job->{child} = $child;

      # Connect the pipe handles to promises via ioloop streams.
      my $handle2promise = sub {
        my ($key, $event, $evproc) = @_;
        return unless exists $child->{$key};
        if (exists $cbs{$key}) {
          my $promise = $job->clone;
          push @promises, $promise;
          my $stream = $self->_handle2stream($child->{$key}, $promise->ioloop,
            close => sub {
              Gitprep::Util::close_pipe($child, $key);
              $promise->resolve("close $key");
            },
            error => sub {
              my $stream = shift;
              $promise->reject(@_, "error $key");
              $stream->close;
            },
            $event => $evproc
          );
          $promise->then(sub {$stream->close; ()}, sub {$stream->close; ()});
          $stream->start;
        } else {
            Gitprep::Util::close_pipe($child, $key);
        }
      };

      $handle2promise->('stdin', 'drain', sub {
        my $stream = shift;
        my $data = $cbs{stdin}->($stream, $options{buffer_size});
        if (defined($data) && length($data)) {
          $stream->write($data);
        } else {
          $stream->close;
        }
      });
      for my $key (qw(stdout stderr)) {
        $handle2promise->($key, 'read', sub {
          my ($stream, $bytes) = @_;
          my $err = $cbs{$key}->($stream, $bytes);
          my $pidmsg = $child->{pid}? "pid $child->{pid} ": '';
          $stream->emit(error => "$pidmsg$key: $err") if $err;
        });
      }

      # Prepare a promise to handle child death.
      my $child_p = $job->clone;
      push @promises, $child_p;
      my $cleanout = sub {
        kill 'KILL', $child->{pid} if Gitprep::Util::child_running($child);
        Gitprep::Util::wait_for($child);
        ()
      };
      $child_p->then($cleanout, $cleanout);

      # Monitor all our promises.
      my $all = Mojo::Promise->all_settled(@promises);
      $all->then(sub {$job->resolve;},
        sub {
         $_->reject(@_) for (@promises, $job);
         ()
        }
      );

      # Connect child death event to its promise.
      my $deathproc;
      $deathproc = $self->app->events->on(child_death => sub {
        unless (Gitprep::Util::child_running($child)) {
          my @errs;
          $self->app->events->unsubscribe(child_death => $deathproc);
          push @errs, $child->{error} if defined $child->{error};
          push @errs, "Killed by signal $child->{signal}" if $child->{signal};
          push @errs, "Exited with code $child->{exit_status}"
            if $child->{exit_status};
          $child_p->reject(@errs) if @errs;
          $child_p->resolve unless @errs;
        }
      });
      $deathproc->();   # Handle possible zombie child.
      $job->catch(sub { $all->reject(@_); () });
    },
    %options);
  return $job;
}

# Create a shell script command job.
#
# Additional option:
#  shell        The shell executable file path.
sub shell {
  my ($self, $script, %options) = @_;
  return $self->command([$options{shell} // $ENV{SHELL} // '/bin/sh',
                        '-c', $script], %options);
}


# Create a curl job.
#
# Optional keyword arguments:
#  url          the target URL.
#  handle       curl easy handle to use. Default is a newly allocated one.
#  stdin        input stream disposition (see below).
#  stdout       output stream disposition.
#  stderr       standard error output disposition.
#  hdrout       header output stream disposition.
#  buffer_size  Maximum data chunk length to use where pertaining.
#               Defaults to 16384.
#  CURLOPT_*    Curl easy option to set in handle.
#
# I/O dispositions can be specified as:
#  a currently open file handle,
#  an open system file descriptor,
#  '&' to use the corresponding global file handle.
#  A reference to a scalar to be used as data buffer for the stream.
#  A subroutine to use as data provider/consumer callback for the stream's data.
#    Input callbacks are called with the easy handle and maximum length
#    in argument and return the input data or '' at EOF. Output callbacks
#    receive the easy handle and output data as argument and return
#    a non-empty string to signal an error.
sub curl {
  my ($self, %options) = @_;
  my $ioloop = $options{ioloop} // Mojo::IOLoop->singleton;
  my $buffer_size = $options{buffer_size} // 16384;

  # Setup and manage the multi handle.
  $ioloop->{curl_promiser} =  Net::Curl::Promiser::Mojo->new($ioloop)
    unless $ioloop->{curl_promiser};
  my $promiser = $ioloop->{curl_promiser};

  # Prepare the easy handle.
  my $easy = $options{handle} // Net::Curl::Easy->new;
  $options{CURLOPT_URL} = $options{url} if exists $options{url};

  return $self->new_job(sub {
    my $job = shift;
    my $aborted = 0;
    my @promises;
    my @toclose;

    # An error is returned by curl_easy_pause if the connection is not
    #  established. Ignore it.
    my $paused = 0;
    my $pause = sub {
      my ($easy, $bitmask) = @_;
      $paused = eval {$easy->pause($bitmask), 1}? $bitmask: 0;
    };

    # Handle input stream disposition (stdin).
    if (exists $options{stdin}) {
      my $callback;
      my $option = $options{stdin} // sub {0};
      $option = \*STDIN if $option eq '&';
      open $option, "<&=:raw", $option if $option =~ /^0|[1-9]\d*$/;
      $option = \$options{stdin} if '' eq ref $option;
      $callback = $option if 'CODE' eq ref $option;
      if ('SCALAR' eq ref $option) {
        my $offset = 0;
        $callback = sub {
          my ($easy, $maxlen) = @_;
          (undef, my $chunk) = unpack("a$offset a$maxlen", $$option);
          $offset += length $chunk;
          return \$chunk;
        };
      }
      elsif (openhandle($option)) {
        open my $fh, '<&', $option;
        my $fifo = Gitprep::Fifo->new;
        my $stream = $self->_handle2stream($fh, $ioloop,
          read => sub {
            $fifo->push($_[1]);
            $_[0]->close if $_[1] eq '';
          }
        );
        $fifo->on(ready => sub {pause->($easy, $paused & ~CURLPAUSE_SEND);});
        $fifo->on(low => sub {$stream->start});
        $fifo->on(high => sub {
          $stream->stop;
          $pause->($easy, $paused & ~CURLPAUSE_SEND);
        });
        $stream->start;
        $callback = sub {
          my $chunk = $fifo->pop($_[1]);
          return \$chunk if defined $chunk;
          $paused |= CURLPAUSE_SEND;
          return CURL_READFUNC_PAUSE;
        };
      }

      $options{CURLOPT_READFUNCTION} = sub {
        $aborted? CURL_READFUNC_ABORT: $callback->(@_)
      } if $callback;
    }

    # Handle error stream disposition (stderr).
    # Use a pipe if needed as curl does not support a callback for this.
    if (exists $options{stderr}) {
      my $option = $options{stderr};
      if (!defined $option) {
        open $option, '>/def/null';
      }
      else {
        $option = \*STDERR if $option eq '&';
        open $option, '>&', $option if openhandle($option);
        open $option, ">>&=:raw", $option if $option =~ /^0|[1-9]\d*$/;
        $option = sub {${$options{stderr}} .= $_[1]} if 'SCALAR' eq ref $option;
        if ('CODE' eq ref $option) {
          my $sub = $option;
          my $promise = $job->clone;
          push @promises, $promise;
          pipe my ($pi, $po);
          push @toclose, $po;
          my $stream = $self->_handle2stream($pi, $ioloop,
            close => sub {
              $promise->resolve;
            },
            read => sub {
              $sub->(@_);
          });
          $promise->{stream} = $stream;
          $stream->start;
          $option = $po;
        }
      }

      $options{CURLOPT_STDERR} = $option if openhandle($option);
    }

    # Handle output stream disposition.
    my $output_func = sub {
      my ($name, $curlopt, $globfh) = @_;
      if (exists $options{$name}) {
        my $callback;
        my $option = $options{$name} // sub {length $_[1]};
        $option = $globfh if $globfh && $option eq '&';
        open $option, ">>&=:raw", $option if $option =~ /^0|[1-9]\d*$/;
        $callback = sub {${$options{$name}} .= $_[1]; length $_[1]}
          if 'SCALAR' eq ref $option;
        $callback = $option if 'CODE' eq ref $option;
        if (openhandle($option)) {
          open my $fh, '>&', $option;
          my $promise = $job->clone;
          push @promises, $promise;
          my $fifo = Gitprep::Fifo->new;
          my $drain;
          $drain = sub {
            unless ($_[0]->is_writing || $fifo->empty) {
              my $chunk = $fifo->pop;
              $_[0]->write($chunk, $drain);
              $promise->resolve if $chunk eq '';
            }
          };

          my $stream = $self->_handle2stream($fh, $ioloop);
          $fifo->on(ready => sub {$drain->($stream)});
          $fifo->on(low => sub {$pause->($easy, $paused & ~CURLPAUSE_RECV)});
          $fifo->on(high => sub {$pause->($easy, $paused | CURLPAUSE_RECV)});
          $callback = sub {
            $fifo->push($_[1]);
            return length $_[1];
          };
        }

        $options{$curlopt} = sub {
          $aborted? CURL_WRITEFUNC_ERROR: $callback->(@_)
        } if $callback;
      }
    };

    # Handle output stream disposition (stdout).
    $output_func->('stdout', 'CURLOPT_WRITEFUNCTION', \*STDOUT);

    # Handle header output disposition (hdrout).
    $output_func->('hdrout', 'CURLOPT_HEADERFUNCTION');

    # Feed curl handle with options.
    while (my ($option, $value) = each %options) {
      $easy->setopt(Net::Curl::Easy->$option, $value)
        if $option =~ m/^CURLOPT_/;
    }

    # Start transfer.
    my $active = 1;
    my $promise = $promiser->add_handle($easy);
    push @promises, $promise;
    $promise->catch(sub {
      $aborted = 1;
      $promiser->cancel_handle($easy) if $active;
      $job->reject(@_);
      ()
    })->finally(sub {$active = 0; close $_ for @toclose;});

    # Wait transfer and I/O settled.
    my $all = Mojo::Promise->all_settled(@promises);
    $all->then(sub {$job->resolve(@_);}, sub {$job->reject(@_); ()});

    # Abort if prematurely rejected.
    $job->catch(sub {$all->reject(@_); $promise->reject(@_); ()});
  }, %options);
}


# Add a job queue to an I/O loop.
sub init_queue {
  my ($self, $ioloop) = @_;
  $ioloop //= Mojo::IOLoop->singleton;
  my $queue = $ioloop->{job_queue};
  unless ($queue) {
    $queue = {
      max_running => 4,
      running => 0,
      fifo => []
    };
    $ioloop->{job_queue} = $queue;
  }
  return $queue;
}

# Run queued jobs under control of the I/O loop.
sub run_queue {
  my ($self, $ioloop) = @_;
  my $queue = $self->init_queue($ioloop);
  while ($queue->{running} < $queue->{max_running} && @{$queue->{fifo}}) {
    my $job = shift @{$queue->{fifo}};
    my $ready = 0;
    if (eval {$ready = $job->{ready}->($job); 1}) {
      if ($ready) {
        my $jobend = sub {
          $queue->{running}--;
          $job->ioloop->next_tick(sub {$self->run_queue($job->ioloop)});
          ()
        };
        $job->then($jobend, $jobend);
        $queue->{running}++;
        $self->run_jobs($job);
      }
    }
    else {
      $job->reject($@);
    }
  }
}

# Enqueue a job for later execution.
#
# Options:
#  ready      a subroutine receiving the job in argument and returns a bool
#             if the job is ready to be started. If this is not the case,
#             disposition should be taken to requeue the job when ready.
#  requeue    a bool telling the call is a requeuing after the job has
#             been discarded by not being ready.
sub enqueue {
  my ($self, $job, %options) = @_;
  my $queue = $self->init_queue($job->ioloop);
  delete $job->{ready};
  $job->{ready} = $options{ready} // sub {1};
  push @{$queue->{fifo}}, $job unless $options{requeue};
  unshift @{$queue->{fifo}}, $job if $options{requeue};
  $job->ioloop->next_tick(sub {$self->run_queue($job->ioloop)});
  return $job;
}

1;
