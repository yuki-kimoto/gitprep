package Gitprep::Jobs;
use Mojo::Base -base;

use strict;
use warnings;

use Mojo::IOLoop;
use Mojo::Promise;
use Scalar::Util qw(openhandle);
use Gitprep::Util;

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
          my $stream = Mojo::IOLoop::Stream->new($child->{$key});
          my $id = $promise->ioloop->stream($stream);
          my %events;
          $events{close} = $stream->on(close => sub {
            $stream->unsubscribe($_ => delete $events{$_}) for (keys %events);
            $promise->resolve("close $key");
          });
          $events{'error'} = $stream->on(error => sub {
            shift;
            $promise->reject(@_, "error $key");
          });
          $events{$event} = $stream->on($event => $evproc);
          my $closeout = sub {
            $stream->unsubscribe($_ => delete $events{$_}) for (keys %events);
            $promise->ioloop->remove($id);
            Gitprep::Util::close_pipe($child, $key);
            ()
          };
          $promise->then($closeout, $closeout);
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
