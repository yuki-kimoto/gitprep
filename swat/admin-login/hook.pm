modify_resource(sub { '/_login/' });

our $logged_in = 0;

if (-f test_root_dir()."/cook.txt"){
    set_response((module_variable('id')).' already logged in');
    our $logged_in = 1;
}
