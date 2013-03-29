package Mojolicious::Plugin::INIConfig;
use Mojo::Base 'Mojolicious::Plugin::Config';
use Config::Tiny;
use File::Spec::Functions 'file_name_is_absolute';
use Mojo::Util qw/encode decode slurp/;

our $VERSION = '0.02';

sub parse {
  my ($self, $content, $file, $conf, $app) = @_;

  my $ct   = Config::Tiny->new;
  my $conf_str = decode('UTF-8', $self->render($content, $file, $conf, $app));
  my $config_ct = $ct->read_string($conf_str);
  my $config = {%$config_ct};
  
  my $err = $ct->errstr;
  die qq{Couldn't parse config "$file": $err} if !$config && $err;
  die qq{Invalid config "$file".} if !$config || ref $config ne 'HASH';

  return $config;
}

sub register {
  my ($self, $app, $conf) = @_;
  
  # Config file
  my $file = $conf->{file} || $ENV{MOJO_CONFIG};
  $file ||= $app->moniker . '.' . ($conf->{ext} || 'ini');

  # Mode specific config file
  my $mode = $file =~ /^(.*)\.([^.]+)$/ ? join('.', $1, $app->mode, $2) : '';

  my $home = $app->home;
  $file = $home->rel_file($file) unless file_name_is_absolute $file;
  $mode = $home->rel_file($mode) if $mode && !file_name_is_absolute $mode;
  $mode = undef unless $mode && -e $mode;

  # Read config file
  my $config = {};

  if (-e $file) { $config = $self->load($file, $conf, $app) }

  # Check for default and mode specific config file
  elsif (!$conf->{default} && !$mode) {
    die qq{Config file "$file" missing, maybe you need to create it?\n};
  }

  # Merge everything
  if ($mode) {
    my $mode_config = $self->load($mode, $conf, $app);
    for my $key (keys %$mode_config) {
      $config->{$key}
        = {%{$config->{$key} || {}}, %{$mode_config->{$key} || {}}};
    }
  }
  if ($conf->{default}) {
    my $default_config = $conf->{default};
    for my $key (keys %$default_config) {
      $config->{$key}
        = {%{$default_config->{$key} || {}}, %{$config->{$key} || {}}, };
    }
  }
  my $current = $app->defaults(config => $app->config)->config;
  for my $key (keys %$config) {
    %{$current->{$key}}
      = (%{$current->{$key} || {}}, %{$config->{$key} || {}});
  }

  return $current;
}

sub render {
  my ($self, $content, $file, $conf, $app) = @_;

  # Application instance and helper
  my $prepend = q[my $app = shift; no strict 'refs'; no warnings 'redefine';];
  $prepend .= q[sub app; *app = sub { $app }; use Mojo::Base -strict;];

  # Render and encode for INI decoding
  my $mt = Mojo::Template->new($conf->{template} || {})->name($file);
  my $ini = $mt->prepend($prepend . $mt->prepend)->render($content, $app);
  return ref $ini ? die $ini : encode 'UTF-8', $ini;
}

1;

=head1 NAME

Mojolicious::Plugin::INIConfig - Mojolicious Plugin to create routes automatically

=head1 CAUTION

B<This module is alpha release. the feature will be changed without warnings.>

=head1 SYNOPSIS

  # myapp.ini
  [section]
  foo=bar
  music_dir=<%= app->home->rel_dir('music') %>

  # Mojolicious
  my $config = $self->plugin('INIConfig');

  # Mojolicious::Lite
  my $config = plugin 'INIConfig';

  # foo.html.ep
  %= $config->{section}{foo}

  # The configuration is available application wide
  my $config = app->config;

  # Everything can be customized with options
  my $config = plugin INIConfig => {file => '/etc/myapp.conf'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::INIConfig> is a INI configuration plugin that
preprocesses its input with L<Mojo::Template>.

The application object can be accessed via C<$app> or the C<app> function. You
can extend the normal config file C<myapp.ini> with C<mode> specific ones
like C<myapp.$mode.ini>. A default configuration filename will be generated
from the value of L<Mojolicious/"moniker">.

The code of this plugin is a good example for learning to build new plugins,
you're welcome to fork it.

=head1 OPTIONS

L<Mojolicious::Plugin::INIConfig> inherits all options from
L<Mojolicious::Plugin::Config> and supports the following new ones.

=head2 default

  # Mojolicious::Lite
  plugin Config => {default => {section => {foo => 'bar'}}};

Default configuration, making configuration files optional.

=head2 template

  # Mojolicious::Lite
  plugin INIConfig => {template => {line_start => '.'}};

Attribute values passed to L<Mojo::Template> object used to preprocess
configuration files.

=head1 METHODS

L<Mojolicious::Plugin::INIConfig> inherits all methods from
L<Mojolicious::Plugin::Config> and implements the following new ones.

=head2 parse

  $plugin->parse($content, $file, $conf, $app);

Process content with C<render> and parse it with L<Config::Tiny>.

  sub parse {
    my ($self, $content, $file, $conf, $app) = @_;
    ...
    $content = $self->render($content, $file, $conf, $app);
    ...
    return $hash;
  }

=head2 register

  my $config = $plugin->register(Mojolicious->new);
  my $config = $plugin->register(Mojolicious->new, {file => '/etc/foo.conf'});

Register plugin in L<Mojolicious> application.

=head2 render

  $plugin->render($content, $file, $conf, $app);

Process configuration file with L<Mojo::Template>.

  sub render {
    my ($self, $content, $file, $conf, $app) = @_;
    ...
    return $content;
  }

=head1 BACKWARDS COMPATIBILITY POLICY

If a feature is DEPRECATED, you can know it by DEPRECATED warnings.
DEPRECATED feature is removed after C<five years>,
but if at least one person use the feature and tell me that thing
I extend one year each time he tell me it.

DEPRECATION warnings can be suppressed
by C<MOJOLICIOUS_PLUGIN_INICONFIG_SUPPRESS_DEPRECATION>
environment variable.

EXPERIMENTAL features will be changed without warnings.

=head1 BUGS

Please tell me bugs if you find bug.

C<< <kimoto.yuki at gmail.com> >>

L<http://github.com/yuki-kimoto/Mojolicious-Plugin-INIConfig>

=head1 COPYRIGHT & LICENSE

Copyright 2013-2013 Yuki Kimoto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut