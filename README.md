# GitPrep

Github clone. you can install portable github system into unix/linux.

# Features

* Github clone
* Perl 5.8.7+ only needed

# Instllation into Unix/Linux system

## Create gitprep user

At first create **gitprep** user. This is not nesessary, but recommended.

    useradd gitprep
    su - gitprep
    cd ~

## Download

Donload zip or tar.gz archive and exapand it and change directory. 

## Setup

You execute the following command. Needed moudles is installed.

    perl cpanm -L extlib --installdeps .

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
  user=gitprep
  group=gitprep
