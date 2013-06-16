# GitPrep

Github clone. you can install portable github system into unix/linux.

<img src="http://cdn-ak.f.st-hatena.com/images/fotolife/p/perlcodesample/20130421/20130421180903_original.png" width="850">

# Features

* Github clone
* Portable. you can install it into your Unix/Linux server.
* Perl 5.8.7+ only needed
* CGI support
* Having built-in web werver, Reverse proxy support

# Installation into Shared Server

Shared Server must support **Linux/Unix**, **Apache**, **SuExec**,
**CGI**, and **PHP5(CGI mode)**.

(PHP is not necessary, if PHP exists, install process is easy
because you don't need to think about permission.)

Many shared server support these,
so you will find sutable server easily.

## Download

You donwload gitprep.

https://github.com/yuki-kimoto/gitprep/archive/latest.zip

You expand zip file. You see the following directory.

    gitprep-latest

Rename this gitprep-latest to gitprep.

    gitprep-latest -> gitprep

## Configuration

GitPrep need git command. you must install git by yourself.

and you must add git command path into config file **gitprep.conf**

    [basic]
    ;;; Git command path
    git_bin=/home/yourname/local/bin/git

## Upload Server by FTP

You upload these directory into server document root by FTP.

## Setup

Access the following URL by browser.

    http://(Your host name)/gitprep/setup/setup.php

(If you don't access PHP file or don't have PHP,
you can use CGI script
please set this CGI script permission to 755)

    http://(Your host name)/gitprep/setup/setup.cgi.

Click Setup button once and wait abount 5 minutes.

## Go to application

If you see result, click "Go to Application".

## You see Internal Server Error

If you see internal server error, you see gitprep/log/production.log.
You know what error is happned.

# Instllation into own Unix/Linux Server

GitPrep have own web server,
so you can execute application very easily.
This is much better than above way
because you don't need to setup Apache environment,
and performance is much much better.

(You can also install GitPrep into Cygwin.
If you want to install GitPrep into Cygwin,
gcc4 and make program are needed.)

## Create gitprep user

At first create **gitprep** user. This is not nesessary, but recommended.

    useradd gitprep
    su - gitprep
    cd ~

## Download

Download tar.gz archive and exapand it and change directory. 

    curl -kL https://github.com/yuki-kimoto/gitprep/archive/latest.tar.gz > gitprep-latest.tar.gz
    tar xf gitprep-latest.tar.gz
    mv gitprep-latest gitprep
    cd gitprep

## Setup

You execute the following command. Needed moudles is installed.

    ./setup.sh

## Test

Do test to check setup process is success or not.

    prove t

If "All tests successful" is shown, setup process is success.

## Configuration

Same as Shared Server's Configuration section.

## Operation

### Start

You can start application start.
Application is run in background, port is **10020** by default.

    ./gitprep

You can access the following URL.
      
    http://localhost:10020
    
If you change port, edit gitprep.conf.
If you can't access this port, you might change firewall setting.

### Stop

You can stop application by **--stop** option.

    ./gitprep --stop

### Operation by root user

If you want to do operation by root user,
you must do some configuration for security.

You add **user** and **group** to **hypnotoad** section
in **gitprep.conf** not to execute application by root user
for security.

    [hypnotoad]
    ...
    user=gitprep
    group=gitprep

Start application

    /home/gitprep/gitprep/gitprep

Stop application

    /home/gitprep/gitprep/gitprep --stop

If you want to start application when os start,
add the application start command to **rc.local** file(Linux).

If you want to make easy to manage gitprep,
Let's create run script in webapp directory.
    
    mkdir -p /webapp
    /home/gitprep/gitprep/create_run_script > /webapp/gitprep
    chmod 755 /webapp/gitprep

You can start and stop application the following command.
    
    # Start or Restart
    /webapp/gitprep
    
    # Stop
    /webapp/gitprep --stop
    
## Developer

If you are developer, you can start application development mode

    ./morbo

You can access the following URL.
      
    http://localhost:3000

If you have git, it is easy to install from git.

    git clone git://github.com/yuki-kimoto/gitprep.git

It is useful to write configuration in ***gitprep.my.conf***
, not gitprep.conf.

## Web Site

[GitPrep Web Site](http://perlcodesample.sakura.ne.jp/gitprep-site/)

## Internally Using Library

* [Config::Tiny](http://search.cpan.org/dist/Config-Tiny/lib/Config/Tiny.pm)
* [DBD::SQLite](http://search.cpan.org/dist/DBD-SQLite/lib/DBD/SQLite.pm)
* [DBI](http://search.cpan.org/dist/DBI/DBI.pm)
* [DBIx::Connector](http://search.cpan.org/dist/DBIx-Connector/lib/DBIx/Connector.pm)
* [DBIx::Custom](http://search.cpan.org/dist/DBIx-Custom/lib/DBIx/Custom.pm)
* [Mojolicious](http://search.cpan.org/~kimoto/DBIx-Custom/lib/DBIx/Custom.pm)
* [Mojolicious::Plugin::INIConfig](http://search.cpan.org/dist/Mojolicious-Plugin-INIConfig/lib/Mojolicious/Plugin/INIConfig.pm)
* [mojo-legacy](https://github.com/jamadam/mojo-legacy)
* [Object::Simple](http://search.cpan.org/dist/Object-Simple/lib/Object/Simple.pm)
* [Validator::Custom](http://search.cpan.org/dist/Validator-Custom/lib/Validator/Custom.pm)

## Copyright & license

Copyright 2013-2013 Yuki Kimoto all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
