package Mojolicious::Plugin::AutoRoute;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '0.12';

sub register {
  my ($self, $app, $conf) = @_;
  
  # Parent route
  my $r = $conf->{route} || $app->routes;
  
  # Top directory
  my $top_dir = $conf->{top_dir} || 'auto';
  $top_dir =~ s#^/##;
  $top_dir =~ s#/$##;
  
  my $condition_name = "__auto_route_plugin_${top_dir}_file_exists";
  
  # Condition
  $app->routes->add_condition($condition_name => sub {
    my ($r, $c, $captures, $pattern) = @_;
    
    my $path = $captures->{__auto_route_plugin_path};
    $path = 'index' unless defined $path;
    
    return if $path =~ /\.\./;
    
    $path =~ s/\/+$//;
    
    my $found;
    for my $dir (@{$c->app->renderer->paths}) {
      if (-f "$dir/$top_dir/$path.html.ep") {
        return 1;
      }
    }
    
    return;
  });
  
  # Index
  $r->route('/')
    ->over($condition_name)
    ->to(cb => sub {
      my $self = shift;
      $self->render("/$top_dir/index", 'mojo.maybe' => 1);
      $self->stash('mojo.finished') ? undef : $self->render_not_found;
    });
  
  # Route
  $r->route('/(*__auto_route_plugin_path)')
    ->over($condition_name)
    ->to(cb => sub {
      my $c = shift;
      
      my $path = $c->stash('__auto_route_plugin_path');
      $path =~ s/\/+$//;
      
      $c->render("/$top_dir/$path", 'mojo.maybe' => 1);
      $c->stash('mojo.finished') ? undef : $c->render_not_found;
    });
  
  # Finish rendering Helper
  $app->helper(finish_rendering => sub {
    warn "finish_rendering is DEPRECATED. no more needed";
  });
}

1;

=head1 NAME

Mojolicious::Plugin::AutoRoute - Mojolicious Plugin to create routes automatically

=head1 CAUTION

B<This is beta release and very experimental. Implementation will be changed without warnings>.

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('AutoRoute');

  # Mojolicious::Lite
  plugin 'AutoRoute';

=head1 DESCRIPTION

L<Mojolicious::Plugin::AutoRoute> is a L<Mojolicious> plugin
to create routes automatically.

Routes corresponding to URL is created .

  TEMPLATES                           ROUTES
  templates/auto/index.html.ep        # /
                /foo.html.ep          # /foo
                /foo/bar.html.ep      # /foo/bar
                /foo/bar/baz.html.ep  # /foo/bar/baz

If you like C<PHP>, this plugin is very good.
You only put file into C<auto> directory.

=head1 EXAMPLE

  use Mojolicious::Lite;
  
  # AutoRoute
  plugin 'AutoRoute';
  
  # Custom routes
  get '/create/:id' => template '/create';
  
  @@ auto/index.html.ep
  /
  
  @@ auto/foo.html.ep
  /foo
  
  @@ auto/bar.html.ep
  /bar
  
  @@ auto/foo/bar/baz.html.ep
  /foo/bar/baz
  
  @@ auto/json.html.ep
  <%
    $self->render(json => {foo => 1});
    return;
  %>
  
  @@ create.html.ep
  /create/<%= $id %>

=head1 OPTIONS

=head2 route

  route => $route;

You can set parent route if you need.
This is L<Mojolicious::Routes> object.
Default is C<$app->routes>.

=head2 top_dir

  top_dir => 'myauto'

Top directory. default is C<auto>.

=head1 FUNCTIONS

=head2 template(Mojolicious::Plugin::AutoRoute::Util)

If you want to create custom route, use C<template> function.

  use Mojolicious::Plugin::AutoRoute::Util 'template';
  
  # Mojolicious Lite
  any '/foo' => template 'foo';

  # Mojolicious
  $r->any('/foo' => template 'foo');

C<template> is return callback to call C<render_maybe>.

=head2 register

  $plugin->register($app);

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
