# GitPrep

Github clone. you can install portable github system into unix/linux.

# Features

* Github clone
* Perl 5.8.7+ only needed

# Instllation into Shared Server (Linux or Unix/Apache/SuExec/CGI/PHP5)

If you want to use GitPrep in Sahred Server,
you can use it.

Sahred Server must support Linux/Unix, Apache, SuExec, CGI, PHP5.
Many shared server support these,
so you will find needed server easily.

you also need git.

## Download

You donwload GitPrep.

https://github.com/yuki-kimoto/gitprep/archive/0.03.zip

You expand zip file. You see the following directory.

    gitprep-0.03

Rename this gitprep-0.03 to gitprep.

    gitprep-0.03 -> gitprep

## Add git command path

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

And click Setup button once and wail abount 5 minutes.

## Go to application

If you see result, click "Go to Application".

## You see Internal Server Error

If you see internal server error, you see gitprep/log/production.log.
You know what error is happned.

# Instllation into your Unix/Linux system

## Create gitprep user

At first create **gitprep** user. This is not nesessary, but recommended.

    useradd gitprep
    su - gitprep
    cd ~

## Download

Download tar.gz archive and exapand it and change directory. 

  curl -kL https://github.com/yuki-kimoto/gitprep/archivegitprep-0.03.tar.gz > gitprep-0.03.tar.gz
  tar xf gitprep-0.03.tar.gz
  cd gitprep-0.03

## Setup

You execute the following command. Needed moudles is installed.

    perl cpanm -n -l extlib Module::CoreList
    perl -Iextlib/lib/perl5 cpanm -n -L extlib --installdeps .

## Operation

### Start

You can start application start.
Application is run in background, port is **10020** by default.

    ./gitprep

You can access the following URL.
      
    http://localhost:10020
    
If you change port, edit gitprep.conf.

### Stop

You can stop application by **--stop** option.

    ./gitprep --stop

### Operation by root user

If you want to do operation by root user,
you must do some works for security.

You add **user** and **group** to **hypnotoad** section in **gitprep.conf**.

  [hypnotoad]
  ...
  user=gitprep
  group=gitprep

### Developer

If you are developer, you can start application development mode

  ./morbo

You can access the following URL.
      
    http://localhost:3000
