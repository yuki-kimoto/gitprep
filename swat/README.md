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
    /home/vagrant/.swat/.cache/5401/prove/virtual/user-create/00.GET.t ..
    ok 1 - POST 127.0.0.1:10020/_login succeeded
    # http headers saved to /home/vagrant/.swat/.cache/5401/prove/PnYO4zo07n.hdr
    # body saved to /home/vagrant/.swat/.cache/5401/prove/PnYO4zo07n
    ok 2 - output match '<!-- Logined as admin -->'
    ok 3 - POST 127.0.0.1:10020/_admin/users succeeded
    # http headers saved to /home/vagrant/.swat/.cache/5401/prove/TGBO407hLu.hdr
    # body saved to /home/vagrant/.swat/.cache/5401/prove/TGBO407hLu
    ok 4 - output match '200 OK'
    ok 5 - POST 127.0.0.1:10020/_admin/user/create succeeded
    # http headers saved to /home/vagrant/.swat/.cache/5401/prove/Ko0uAq3HsW.hdr
    # body saved to /home/vagrant/.swat/.cache/5401/prove/Ko0uAq3HsW
    ok 6 - output match '200 OK'
    ok 7 - POST 127.0.0.1:10020/_login/ succeeded
    # http headers saved to /home/vagrant/.swat/.cache/5401/prove/9rloDnrVEx.hdr
    # body saved to /home/vagrant/.swat/.cache/5401/prove/9rloDnrVEx
    ok 8 - output match /Location:\s+\S+/swat-user/
    ok 9 - GET 127.0.0.1:10020/swat-user succeeded
    # http headers saved to /home/vagrant/.swat/.cache/5401/prove/ZQgAKjP6H4.hdr
    # body saved to /home/vagrant/.swat/.cache/5401/prove/ZQgAKjP6H4
    ok 10 - output match '<!-- Logined as swat-user -->'
    ok 11 - server response is spoofed
    # response saved to /home/vagrant/.swat/.cache/5401/prove/XVnAUYRkgU
    ok 12 - output match 'OK'
    1..12
    ok
    /home/vagrant/.swat/.cache/5401/prove/virtual/login/00.GET.t ........
    ok 1 - server response is spoofed
    # response saved to /home/vagrant/.swat/.cache/5401/prove/n0gWgTYNkH
    ok 2 - output match 'admin already logged in'
    ok 3 - server response is spoofed
    # response saved to /home/vagrant/.swat/.cache/5401/prove/M_GQEYmlca
    ok 4 - output match 'OK'
    1..4
    ok
    All tests successful.
    Files=2, Tests=16,  0 wallclock secs ( 0.03 usr  0.00 sys +  0.12 cusr  0.02 csys =  0.17 CPU)
    Result: PASS
    

# Author

Alexey Melezhik


