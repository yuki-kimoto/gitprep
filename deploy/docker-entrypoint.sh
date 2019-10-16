#!/bin/sh

# Making all required files if they are not existing.
test -f /etc/ssh/ssh_host_ecdsa_key || \
    /usr/bin/ssh-keygen -q -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -C '' -N ''
test -f /etc/ssh/ssh_host_rsa_key || \
    /usr/bin/ssh-keygen -q -t rsa -f /etc/ssh/ssh_host_rsa_key -C '' -N ''
test -f /etc/ssh/ssh_host_ed25519_key || \
    /usr/bin/ssh-keygen -q -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -C '' -N ''

# Now start SSH daemon.
/usr/sbin/sshd

# GitPrep restrict max post message size 10MB(This is default of Mojolicious)
# We overwrite the value to 1GB :
export MOJO_MAX_MESSAGE_SIZE=1024000000 

# Start GitPrep and tail log file
su - gitprep -s /bin/bash -c '/home/gitprep/gitprep/gitprep'
tail -f /home/gitprep/gitprep/log/production.log
