#!/bin/sh

# you need to give the project user ssh access on the remote server.
# this is usually only necessary on older B&Y installations — ymmv
#
# ssh INSERT_SSH_SERVER_HERE
# sudo mkdir /home/e2e_project/.ssh && \
# sudo cp ~/.ssh/authorized_keys /home/e2e_project/.ssh/ && \
# sudo chown -R e2e_project:e2e_project /home/e2e_project/.ssh

rsync -arvzi -e 'ssh -p 30000' --progress media e2e_project@INSERT_SSH_SERVER_HERE:/sites/prod/e2e_project/
