run_swat_module(
    POST => "_login",
    {
        id => config()->{main}->{admin_user},
        password => config()->{main}->{admin_pass}

    }
);


#run_swat_module(
#    POST => "user-delete",
#    {
#        user => 'foo'
#    }
#);

set_response('OK');
