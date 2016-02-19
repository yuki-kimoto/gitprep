# SYNOPSIS

[swat](https://github.com/melezhik/swat) integration tests for gitgrep

# Check list:

* log in as admin user
* create user account ( remove old one if necessary )
* login as regular user 

# Installation

    yum install curl
    cpanm install swat

# Configuration

Admin account _SHOULD BE_ pre installed, test suite does not create one.

Once account is created change admin login and password to reflect actual one:

    nano suite.ini

    [main]
    
    admin_user = admin
    admin_pass = admin


# Running tests

    # run against http://localhost:10020
    swat

    # or specific url
    swat ./ http://gitgrep/foo/bar/baz

# Sample output

    vagrant@Debian-jessie-amd64-netboot:~/my/gitprep/swat$ swat
    /home/vagrant/.swat/.cache/6053/prove/virtual/user-create/00.GET.t ..
    ok 1 - POST 127.0.0.1:10020/_login/ succeeded
    # http headers saved to /home/vagrant/.swat/.cache/6053/prove/4TsYnZ2TH4.hdr
    # body saved to /home/vagrant/.swat/.cache/6053/prove/4TsYnZ2TH4
    ok 2 - output match '<!-- Logined as admin -->'
    ok 3 - POST 127.0.0.1:10020/_admin/users succeeded
    # http headers saved to /home/vagrant/.swat/.cache/6053/prove/G8iDlvi97X.hdr
    # body saved to /home/vagrant/.swat/.cache/6053/prove/G8iDlvi97X
    ok 4 - output match '200 OK'
    ok 5 - POST 127.0.0.1:10020/_admin/user/create succeeded
    # http headers saved to /home/vagrant/.swat/.cache/6053/prove/LXizpHfmDB.hdr
    # body saved to /home/vagrant/.swat/.cache/6053/prove/LXizpHfmDB
    ok 6 - output match '200 OK'
    ok 7 - POST 127.0.0.1:10020/_login/ succeeded
    # http headers saved to /home/vagrant/.swat/.cache/6053/prove/iXyojrEwJg.hdr
    # body saved to /home/vagrant/.swat/.cache/6053/prove/iXyojrEwJg
    ok 8 - output match /Location:\s+\S+/swat100/
    ok 9 - GET 127.0.0.1:10020/swat100 succeeded
    # http headers saved to /home/vagrant/.swat/.cache/6053/prove/gGRn_b4A7q.hdr
    # body saved to /home/vagrant/.swat/.cache/6053/prove/gGRn_b4A7q
    ok 10 - output match '<!-- Logined as swat100 -->'
    ok 11 - server response is spoofed
    # response saved to /home/vagrant/.swat/.cache/6053/prove/qkL9jcb2zM
    ok 12 - output match 'OK'
    1..12
    ok
    /home/vagrant/.swat/.cache/6053/prove/virtual/login/00.GET.t ........
    ok 1 - server response is spoofed
    # response saved to /home/vagrant/.swat/.cache/6053/prove/6gQOs36I40
    ok 2 - output match 'OK'
    1..2
    ok
    All tests successful.
    Files=2, Tests=14,  0 wallclock secs ( 0.02 usr  0.01 sys +  0.12 cusr  0.02 csys =  0.17 CPU)
    Result: PASS
            

# Author

Alexey Melezhik


