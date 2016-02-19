our $user_logged_in = 0;

if (-f test_root_dir()."/user_cook.txt"){
    set_response('user already logged in');
    our $user_logged_in = 1;
}

modify_resource(sub { '/_login/' });
