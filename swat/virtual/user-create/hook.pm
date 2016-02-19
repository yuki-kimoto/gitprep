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
        user => config()->{main}->{reg_user}
    }
);

run_swat_module(
    POST => "/user-create",
    {
        id          => config()->{main}->{reg_user},
        password    => config()->{main}->{reg_user_pass}
    }
);


run_swat_module(
    POST => "_user_login",
    {
        id          => config()->{main}->{reg_user},
        password    => config()->{main}->{reg_user_pass}
    }
);

run_swat_module(
    GET => "/user-page",
    {
        id => config()->{main}->{reg_user}
    }
);


set_response('OK');
