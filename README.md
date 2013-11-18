# GitPrep

Github clone. You can install portable github system into Unix/Linux.

<img src="http://cdn-ak.f.st-hatena.com/images/fotolife/p/perlcodesample/20130421/20130421180903_original.png" width="850">

# Features

* Github clone. GitPrep have same interface as GitHub.
* Portable. You can install GitPrep into your Unix/Linux server.
* Support cygwin on Windows(need gcc4 package). You can install GitPrep into Windows.
* Only needs Perl 5.8.7+.
* Smart HTTP support, you can pull and push via HTTP
* CGI support, and having built-in web server, Reverse proxy support.
* SSL support.

# Installation into Shared Server

Shared Server must support **Linux/Unix**, **Apache**, **SuExec**,
**CGI**, and **PHP5(CGI mode)**.

(*PHP* is not necessary, if PHP exists, the install process is easy
because you do not need to think about permissions.)

Many shared servers support these,
so you will be able to find a suitable server easily.

## Download

First you need to download gitprep.

https://github.com/yuki-kimoto/gitprep/archive/latest.zip

Expand the zip file. You will see the following directory.

    gitprep-latest

Rename the gitprep-latest directory to gitprep.

    gitprep-latest -> gitprep

## Configuration

GitPrep needs the git command. You must install git by yourself.

You must add the correct git command path to the **gitprep.conf** config file.

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

Click Setup button once and wait about 5 minutes.

## Go to application

If you see result, click "Go to Application".

## Internal Server Error

If you receive an internal server error, look at the log file (gitprep/log/production.log)
to see what the problem occurred.

# Installation into own Unix/Linux Server

GitPrep has its own web server,
so you can start using the application very easily.
This is much better than the way shown above
because you do not need to setup the Apache environment
and performance will be much better.

(You can also install GitPrep into Cygwin.
If you want to install GitPrep into Cygwin,
gcc4 and make program are needed.)

## Create gitprep user

Create a **gitprep** user. This is not necessary, but recommended.

    useradd gitprep
    su - gitprep
    cd ~

## Download

Download tar.gz archive, expand it and change directory.

    curl -kL https://github.com/yuki-kimoto/gitprep/archive/latest.tar.gz > gitprep-latest.tar.gz
    tar xf gitprep-latest.tar.gz
    mv gitprep-latest gitprep
    cd gitprep

## Setup

To setup GitPrep, execute the following command. All of the needed modules will be installed.

    ./setup.sh

## Test

Run the test to check if the setup process was successful or not.

    prove t

If "All tests successful" is shown, the setup process was successful.

## Configuration

Same as Shared Server's Configuration section.

## Operation

### Start

You can start the application by running the provided gitprep script.
The application is run in the background and the port is **10020** by default.

    ./gitprep

Then access the following URL.

    http://localhost:10020

If you want to change the port, edit gitprep.conf.
If you cannot access this port, you might change the firewall settings.

### Stop

You can stop the application by adding the **--stop** option.

    ./gitprep --stop

### Operation from root user

You can manage the application from the root user.

Start the application

    sudo -u gitprep /home/gitprep/gitprep/gitprep

Stop the application

    sudo -u gitprep /home/gitprep/gitprep/gitprep --stop

If you want to start the application when the OS starts,
add the start application command to **rc.local**(Linux).

If you want to make it easy to manage gitprep,
then create a run script.

    mkdir -p /webapp
    echo '#!/bin/sh' > /webapp/gitprep
    echo 'su - gitprep -c "/home/gitprep/gitprep/gitprep $*"' >> /webapp/gitprep
    chmod 755 /webapp/gitprep

You can start and stop the application with the following command.

    # Start or Restart
    /webapp/gitprep

    # Stop
    /webapp/gitprep --stop

## Developer

If you are a developer, you can start the application in development mode.

    ./morbo

Then access the following URL.

    http://localhost:3000

If you have git, it is easy to install from git.

    git clone git://github.com/yuki-kimoto/gitprep.git

It is useful to write configuration in ***gitprep.my.conf***, not gitprep.conf.

## FAQ

### blame don't work

In Gitprep, blame page use "git blame --line-porcelain". In old git, there is no --line-porcelain option.
We don't know when --line-porcelain was added to git.
At least, blame page work well in git 1.8.2.1.

### How to upgrade GitPrep

It is ver easy. you only overwrite all files except for "gitprep.conf".

If you want to upgrade by "git pull", you can do it.
you create "gitprep.my.conf" copied from "gitprep.my.conf",
and do "git pull"

### I can't push large repository by http protocal

Maybe http.postBuffer value of git config is small. Input the following command to increase this size.

    git config http.postBuffer 104857600

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
* [Text::Markdown::Discount](http://search.cpan.org/dist/Text-Markdown-Discount/lib/Text/Markdown/Discount.pm)
* [Validator::Custom](http://search.cpan.org/dist/Validator-Custom/lib/Validator/Custom.pm)

## Sister project

These are my Perl web application projects.

* [WebDBViewer](https://github.com/yuki-kimoto/webdbviewer) - Database viewer to see database information on web browser.
* [TaskDeal](http://perlcodesample.sakura.ne.jp/taskdeal-site/) - Setup or deploy multiple environments on web browser. Ruby Chef alternative tool.

## Copyright & license

Copyright 2012-2013 Yuki Kimoto. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
