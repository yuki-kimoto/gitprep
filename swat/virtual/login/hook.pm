run_swat_module(
    POST => "_login",
    {
        id => config()->{main}->{admin_user},
        password => config()->{main}->{admin_pass}

    }
);
set_response('OK');
