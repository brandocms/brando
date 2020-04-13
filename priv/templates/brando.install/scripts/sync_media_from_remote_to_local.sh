#!/bin/sh

# you need to give the project user ssh access on the remote server.
#
# ssh YOUR_SERVER
# sudo mkdir /home/<%= application_name %>/.ssh && \
# sudo cp ~/.ssh/authorized_keys /home/<%= application_name %>/.ssh/ && \
# sudo chown -R <%= application_name %>:<%= application_name %> /home/<%= application_name %>/.ssh

rsync -arvzi -e 'ssh -p 30000' --progress <%= application_name %>@INSERT_SSH_SERVER_HERE:/sites/prod/a_huseby/media/ media
