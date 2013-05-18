package Mojolicious::Plugin::AutoRoute;
use Mojo::Base 'Mojolicious::Plugin';

our $VERSION = '0.09';

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
    ->to(cb => sub { shift->render("/$top_dir/index", 'mojo.maybe' => 1) });
  
  # Route
  $r->route('/(*__auto_route_plugin_path)')
    ->over($condition_name)
    ->to(cb => sub {
      my $c = shift;
      
      my $path = $c->stash('__auto_route_plugin_path');
      
      $c->render("/$top_dir/$path", 'mojo.maybe' => 1);
    });
  
  # Finish rendering Helper
  $app->helper(finish_rendering => sub {
    my $self = shift;
    
    $self->stash->{'mojo.routed'} = 1;
    $self->rendered;
    
    return $self;
  });
}

1;

=head1 NAME

Mojolicious::Plugin::AutoRoute - Mojolicious Plugin to create routes automatically

=head1 CAUTION

B<This is beta release. Implementation will be changed without warnings>. 

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

=head1 OPTIONS

=head2 route

  route => $route;

You can set parent route if you need.
This is L<Mojolicious::Routes> object.
Default is C<$app->routes>.

=head2 top_dir

  top_dir => 'myauto'

Top directory. default is C<auto>.

=head1 METHODS

L<Mojolicious::Plugin::AutoRoute> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head1 HELPER

=head2 finish_rendering

You can render data, json, not found and exeption from template
using C<finish_rendering> helper.

  @@ index.html.ep
  $self->render(data => 'foo');
  $self->finish_rendering;
  return;

  @@ index.html.ep
  $self->render(json => {foo => 1});
  $self->finish_rendering;
  return;

  @@ index.html.ep
  $self->render_not_found;
  $self->finish_rendering;
  return;

  @@ index.html.ep
  $self->render_exception;
  $self->finish_rendering;
  return;

=head2 register

  $plugin->register($app);

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
