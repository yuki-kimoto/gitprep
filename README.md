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
If you don't yet set user.name and user.email, you must set them.

    git config --global user.name "gitprep"
    git config --global user.email "gitprep@example.com"

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

It is very easy. you only overwrite all files except for "gitprep.conf".

If you want to upgrade by "git pull", you can do it.
you create "gitprep.my.conf" copied from "gitprep.my.conf",
and do "git pull"

If you get a rainbow unicorn t-rex error after upgrading, you might be missing
a new CPAN dependency. Rerun the /setup/setup.php on brower
or rerun setup.sh on command line.

### I can't push large repository by http protocol

There are some reasons.

**1. Git version is old**

If you see "error: RPC failed; result=56, HTTP code = 200" , your git maybe old.
Please upgrade to latest git. I checked git version 1.8.5.5.

**2. GitPrep restriction**

GitPrep restrict max post message size 10MB(This is default of Mojolicious)

You maybe see the following error

    Delta compression using up to 4 threads.
    Compressing objects: 100% (17830/17830), done.
    Writing objects: 100% (18281/18281), 687.05 MiB | 129.92 MiB/s, done.
    Total 18281 (delta 295), reused 18281 (delta 295)
    error: RPC failed; result=22, HTTP code = 413
    fatal: The remote end hung up unexpectedly
    fatal: The remote end hung up unexpectedly

Please increase increase the value of MOJO_MAX_MESSAGE_SIZE
    
    # 1GB
    export MOJO_MAX_MESSAGE_SIZE=1024000000

**3. git restriction**

git restrict post max size via http protocol.
http.postBuffer value of git config is maybe small.

You maybe see the following error message.

    error: RPC failed; result=56, HTTP code = 200
    fatal: The remote end hung up unexpectedly
    Counting objects: 18281, done.
    Delta compression using up to 4 threads.
    Compressing objects: 100% (17830/17830), done.
    Writing objects: 100% (18281/18281), 687.05 MiB | 133.23 MiB/s, done.
    Total 18281 (delta 295), reused 18281 (delta 295)
    fatal: The remote end hung up unexpectedly
    Everything up-to-date

Please increase the value of http.postBuffer.
    
    # 1GB
    git config http.postBuffer 1024000000

### I can't create repository and see error message when I create repository with readme

If you see the following error message in log/production.log

    [Wed Feb 12 15:27:02 2014] [error] ... Can't execute git commit ...

you need to set User name and Email of git.
Please set user.name and user.email.

    git config --global user.name "gitprep"
    git config --global user.email "gitprep@example.com"

### How to use reverse proxy?

You can use GitPrep via reverse proxy access

         ----------------------------     ------------
    ---->| Web Server(Reverse proxy)|---->|GitPrep   |
    <----| (Apache, etc)            |<----|          |
         ----------------------------     ------------

I show apache config example.
You can use Name virtual host.
    
    # HTTP
    <VirtualHost *:80>

      ServerName myhost.com
      <Proxy *>
        Order deny,allow
        Allow from all
      </Proxy>
      
      ProxyRequests Off
      ProxyPreserveHost On
      ProxyPass / http://localhost:10020/ keepalive=On
      ProxyPassReverse / http://localhost:10020/
      RequestHeader set X-Forwarded-HTTPS "0"
        
    </VirtualHost>

If you use GitPrep vis https, you should set X-Forwarded-HTTPS Request Header.

    # HTTPS
    <VirtualHost *:443>

      ServerName myhost.com
      <Proxy *>
        Order deny,allow
        Allow from all
      </Proxy>
      
      ProxyRequests Off
      ProxyPreserveHost On
      ProxyPass / http://localhost:10020/ keepalive=On
      ProxyPassReverse / http://localhost:10020/
      RequestHeader set X-Forwarded-HTTPS "1"
    </VirtualHost>

### How to import already existing repositories?

You can import already existing repositories by **script/import_rep** script.

    cd script
    ./import_rep -u kimoto rep_dir

**-u** is user name. rep_dir must contains git respoitories like the following.

    rep_dir/project1.git
           /project2.git
           /project3.git
           /project3.git

If **description** file exists in git repository, it is copied.

### I can't add collabortor more than one

This is GitPrep bug before version 1.5.1.
Please use after version 1.5.2.

If you contine to use GitPrep before version 1.5.1,
collaboration table is broken.
Please fix it by the following way.

    # Run SQLite client
    sqlite3 data/gitprep.db
    
    # drop collaboration table
    drop table collaboration;
    
    # Restart
    ./gitprep

## I want to set time zone.

OK. GitPrep suport time zone. You can set time_zone option in conig file.

    [basic]
    ;;; Time Zone
    ;;; GitPrep time zone is GMT by default
    ;;; You can set your local time zone.
    time_zone=+9:00

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
* [Text::Markdown::Hoedown](http://search.cpan.org/~tokuhirom/Text-Markdown-Hoedown-1.01/lib/Text/Markdown/Hoedown.pm)
* [Validator::Custom](http://search.cpan.org/dist/Validator-Custom/lib/Validator/Custom.pm)

## Sister project

These are my Perl web application projects.

* [WebDBViewer](http://perlcodesample.sakura.ne.jp/webdbviewer-site/) - Database viewer to see database information on web browser.
* [TaskDeal](http://perlcodesample.sakura.ne.jp/taskdeal-site/) - Setup or deploy multiple environments on web browser. Ruby Chef alternative tool.

## Copyright & license

Copyright 2012-2013 Yuki Kimoto. All rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
