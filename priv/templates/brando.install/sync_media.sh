# 1. chmod +x this
# 2. older brando projects might have to ssh in and copy ssh keys first
#
rsync -arvz -e 'ssh -p 30000' --progress media <%= application_name %>@INSERT_SSH_SERVER_HERE:/sites/prod/<%= application_name %>/