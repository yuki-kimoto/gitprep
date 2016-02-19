run_swat_module(
    POST => "_login",
    {
        id => config()->{main}->{admin_user},
        password => config()->{main}->{admin_pass}

    }
);


run_swat_module(
    POST => "/user-delete",
    {
        user => 'swat-user'
    }
);

run_swat_module(
    POST => "/user-create",
    {
        id => 'swat-user',
        password => 'swat-pass'
    }
);


run_swat_module(
    POST => "_user_login",
    {
        id => 'swat-user',
        password => 'swat-pass'
    }
);

run_swat_module(
    GET => "/user-page",
    {
        id => 'swat-user'
    }
);


set_response('OK');
