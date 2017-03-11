#!/usr/bin/env python
import os
import random
import re

from datetime import datetime
from fabric.api import *
from fabric.contrib.files import exists as _exists
from fabric.contrib.console import confirm
from fabric.context_managers import settings as _settings
from fabric.colors import red, green, yellow, cyan, blue
from fabric.operations import prompt
from fabric.utils import abort

VERSION_NUMBER = '2.0.0'

#
# Project-specific setup.

PROJECT_NAME = '<%= application_name %>'
PROD_URL = 'http://somesite.com'
DB_PASS = 'prod_database_password'

SSH_USER = 'username'
SSH_PASS = 'sudoer_pass'
SSH_HOST = 'host.net'
SSH_PORT = 30000

#
# Shhh, don't be so loud.

# output['status'] = True
# output['stdout'] = False
# output['warnings'] = True
# output['exceptions'] = False
# output['running'] = False
# output['user'] = True
# output['stderr'] = True
# output['aborts'] = True
# output['debug'] = False

#
# General setup

GLUE_SETTINGS = {
    'project_name': PROJECT_NAME,
    'project_group': 'web',
    'ssh_user': SSH_USER,
    'ssh_host': SSH_HOST,
    'ssh_port': SSH_PORT,
    'prod': {
        'project_base': '/sites/prod',
        'process_name': '%s_prod' % PROJECT_NAME,
        'db_name': "%s_prod" % PROJECT_NAME,
        'db_user': PROJECT_NAME,
        'db_pass': DB_PASS,
        'repo': PROJECT_NAME,
        'git_branch': 'master',
        'public_path': 'priv',
        'media_path': 'media',
    },
    'staging': {
        'project_base': '/sites/staging',
        'process_name': '%s_staging' % PROJECT_NAME,
        'db_name': "%s_staging" % PROJECT_NAME,
        'db_user': PROJECT_NAME,
        'db_pass': DB_PASS,
        'repo': PROJECT_NAME,
        'git_branch': 'master',
        'public_path': 'priv',
        'media_path': 'media',
    }
}


def _get_project_version():
    with open('mix.exs') as f:
        contents = f.read()
        r = re.compile('\@version \"(?P<version>.*)\"')
        result = r.search(contents)
        if result:
            return result.group('version')
        else:
            raise RuntimeError("Version not found in mixfile. Make sure it is set as `@version \"0.1.0\"`")

def _get_bds_version():
    return VERSION_NUMBER

print "--------------------------------------------------------------"
print blue('& brando deployment script v%s | copyright twined 2010-%s'
           % (_get_bds_version(), datetime.now().year))
print "--------------------------------------------------------------"
print ""


def prod():
    """
    Use the production server
    """
    # the flavor of the django environment
    env.flavor = 'prod'
    # the process name, also the base name
    env.procname = GLUE_SETTINGS['prod']['process_name']

    # username for the ssh connection
    env.user = GLUE_SETTINGS['ssh_user']
    # hostname for the ssh connection
    env.host = GLUE_SETTINGS['ssh_host']
    # port for the ssh connection
    env.port = GLUE_SETTINGS['ssh_port']
    # here we build the hosts string
    env.hosts = ['%s@%s:%s' % (env.user, env.host, env.port)]
    # password to use
    if SSH_PASS != '':
        env.passwords = {'%s@%s:%s' % (env.user, env.host, env.port): SSH_PASS}
    # project base
    env.project_base = GLUE_SETTINGS['prod']['project_base']
    # the path to clone our git repo into
    env.path = os.path.join(GLUE_SETTINGS['prod']['project_base'],
                            GLUE_SETTINGS['project_name'])
    # name of the repo we are cloning
    env.repo = '%s' % GLUE_SETTINGS['prod']['repo']
    # branch name to clone, or empty for master
    env.branch = GLUE_SETTINGS['prod']['git_branch']

    # the user we will create on host, also runs manage.py tasks etc.
    env.project_user = GLUE_SETTINGS['project_name']
    # the group we add the user to. this is what the project path
    # gets chowned to
    env.project_group = GLUE_SETTINGS['project_group']

    # the postgres database username we create
    env.db_user = GLUE_SETTINGS['prod']['db_user']
    # name of the postgres database we create
    env.db_name = GLUE_SETTINGS['prod']['db_name']
    # password to the postgres database user
    env.db_pass = GLUE_SETTINGS['prod']['db_pass']
    # full path to our project's public/ directory
    env.public_path = os.path.join(env.path,
                                   GLUE_SETTINGS['prod']['public_path'])
    # full path to our project's media directory
    env.media_path = os.path.join(env.public_path,
                                  GLUE_SETTINGS['prod']['media_path'])
    # application name
    env.project_name = GLUE_SETTINGS['project_name']


def staging():
    """
    Use the staging server
    """
    # the flavor of the django environment
    env.flavor = 'staging'
    # the process name, also the base name
    env.procname = GLUE_SETTINGS['staging']['process_name']

    # username for the ssh connection
    env.user = GLUE_SETTINGS['ssh_user']
    # hostname for the ssh connection
    env.host = GLUE_SETTINGS['ssh_host']
    # port for the ssh connection
    env.port = GLUE_SETTINGS['ssh_port']
    # here we build the hosts string
    env.hosts = ['%s@%s:%s' % (env.user, env.host, env.port)]

    # project base
    env.project_base = GLUE_SETTINGS['staging']['project_base']
    # the path to clone our git repo into
    env.path = os.path.join(GLUE_SETTINGS['staging']['project_base'],
                            GLUE_SETTINGS['project_name'])
    # name of the repo we are cloning
    env.repo = '%s' % GLUE_SETTINGS['staging']['repo']
    # branch name to clone, or empty for master
    env.branch = GLUE_SETTINGS['staging']['git_branch']

    # the user we will create on host, also runs manage.py tasks etc.
    env.project_user = GLUE_SETTINGS['project_name']
    # the group we add the user to. this is what the project path
    # gets chowned to
    env.project_group = GLUE_SETTINGS['project_group']

    # the postgres database username we create
    env.db_user = GLUE_SETTINGS['staging']['db_user']
    # name of the postgres database we create
    env.db_name = GLUE_SETTINGS['staging']['db_name']
    # password to the postgres database user
    env.db_pass = GLUE_SETTINGS['staging']['db_pass']
    # full path to our project's public/ directory
    env.public_path = os.path.join(env.path,
                                   GLUE_SETTINGS['staging']['public_path'])
    # full path to our project's media directory
    env.media_path = os.path.join(env.public_path,
                                  GLUE_SETTINGS['staging']['media_path'])
    # application name
    env.project_name = GLUE_SETTINGS['project_name']


def bootstrap_release():
    """
    Bootstraps and provisions project RELEASE on host
    """
    require('hosts')
    version = _get_project_version()

    _warn('''
        Deploying %s v%s.\r\n
        This is a potientially dangerous operation. Make sure you have\r\n
        all your ducks in a row, and that you have checked the configuration\r\n
        files both in etc/ and in the fabfile.py itself!
    ''' % (PROJECT_NAME, version))

    _confirmtask()

    createuser()
    create_path()

    build_release()
    copy_release_from_docker(version)
    upload_release(version)
    unpack_release(version)

    upload_media()
    upload_etc()
    createdb()

    ensure_log_directory_exists()

    supervisorcfg()
    nginxcfg()
    logrotatecfg()

    dump_local_db_and_load_db_on_remote()

    restart()
    _success()
    _notify_build_complete(version)


def deploy_release():
    """
    Build release on local Docker, upload and unpack to remote before restarting
    """
    version = _get_project_version()
    print(yellow('==> deploy release %s v%s' % (PROJECT_NAME, version)))
    if not confirm("Is the version correct?"):
        abort("Aborting")

    build_release()
    copy_release_from_docker(version)
    upload_release(version)
    unpack_release(version)
    ensure_log_directory_exists()
    restart()
    _success()
    _notify_build_complete(version)


def build_release():
    """
    Build release with docker
    """
    print(yellow('==> building local release with docker...'))
    local('docker build -t twined/%s .' % env.project_name)


def copy_release_from_docker(version):
    """
    Copy release tarball out from Docker image
    """
    print(yellow('==> copying release archive from docker to release-archives/'))
    local('mkdir -p release-archives')
    local('docker run --rm --entrypoint cat twined/%s /opt/app/_build/prod/rel/%s/releases/%s/%s.tar.gz > release-archives/%s_%s.tar.gz' % (
        env.project_name,
        env.project_name,
        version,
        env.project_name,
        env.project_name,
        version))


def upload_release(version):
    """
    Upload release to target
    """
    print(yellow('==> uploading release to target host'))
    put('release-archives/%s_%s.tar.gz' % (env.project_name, version), '%s' % env.path, use_sudo=True)
    print(yellow('==> chowning archive'))
    _setowner(os.path.join(env.path, '%s_%s.tar.gz' % (env.project_name, version)))
    print(yellow('==> chmoding archive'))
    _setperms('660', os.path.join(env.path, '%s_%s.tar.gz' % (env.project_name, version)))


def unpack_release(version):
    """
    Unpack release at target, delete old stuff + archive
    """
    with cd(env.path), shell_env(HOME='/home/%s' % env.project_user):
        print(red('==> deleting old release'))
        sudo('rm -rf bin erts-7.2 lib releases running-config', user=env.project_user)
        print(yellow('==> unpacking release'))
        sudo('tar xvf %s_%s.tar.gz' % (env.project_name, version), user=env.project_user)
        print(yellow('==> archiving release'))
        sudo('mkdir -p release-archives', user=env.project_user)
        sudo('mv %s_%s.tar.gz release-archives/%s_%s.tar.gz' % (env.project_name, version, env.project_name, version), user=env.project_user)

    fixprojectperms()


def grant_db():
    """
    Grant privileges on remote database
    """
    require('hosts')
    with _settings(warn_only=True):
        print(yellow('==> granting privileges on database %s to user %s' % (env.db_name, env.db_user)))
        sudo('psql -c "grant all privileges on database %s to %s;"' % (env.db_name, env.db_user), user='postgres')
        sudo('for tbl in `psql -qAt -c "select tablename from pg_tables where schemaname = \'public\';" %s` ; do  psql -c "alter table \"$tbl\" owner to %s" %s ; done' % (env.db_name, env.db_user, env.db_name), user='postgres')
        sudo('for tbl in `psql -qAt -c "select sequence_name from information_schema.sequences where sequence_schema = \'public\';" %s` ; do  psql -c "alter table \"$tbl\" owner to %s" %s ; done' % (env.db_name, env.db_user, env.db_name), user='postgres')
        sudo('for tbl in `psql -qAt -c "select table_name from information_schema.views where table_schema = \'public\';" %s` ; do  psql -c "alter table \"$tbl\" owner to %s" %s ; done' % (env.db_name, env.db_user, env.db_name), user='postgres')


def ensure_log_directory_exists():
    """
    Ensure that remote log directory exists
    """
    require('hosts')
    print(yellow('==> ensure log directory exists'))
    if not _exists(os.path.join(env.path, "log")):
        print(yellow('==> creating %s/log as %s' % (env.path, env.project_user)))
        sudo('mkdir -p %s/log' % env.path, user=env.project_user)

    if not _exists(os.path.join(env.path, "acme-challenge")):
        print(yellow('==> creating %s/acme-challenge/.well-known/acme-challenge as %s' % (env.path, env.project_user)))
        sudo('mkdir -p %s/acme-challenge/.well-known/acme-challenge' % env.path, user=env.project_user)

    fixprojectperms()


def create_path():
    """
    Create remote project path
    """
    require('hosts')
    if not _exists(env.project_base):
        print(yellow('==> create remote project base dir: %s' % env.project_base))
        sudo('mkdir -p %s' % env.project_base)
        print(yellow('==> chown remote project base dir to %s:%s' % (SSH_USER, env.project_group)))
        sudo('chown %s:%s -R "%s"' % (SSH_USER, env.project_group, env.project_base))
        print(yellow('==> set g+w on remote project base dir'))
        _setperms('g+w', env.project_base)

    if not _exists(env.path):
        print(yellow('==> creating remote project dir: %s as %s' % (env.path, env.project_user)))
        sudo('mkdir -p %s' % env.path, user=env.project_user)

    create_acme_dir()
    fixprojectperms()


def migrate_release():
    """
    Run database migrations for release
    """
    require('hosts')
    print(yellow('==> running db migrations escript for remote release'))
    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user):
        sudo('bin/%s escript bin/release_tasks.escript migrate' % env.project_name,
             user=env.project_user)


def dump_localdb():
    """
    Dumps local _dev database
    """
    print(yellow('==> dumping local database %s -> sql/db_dump_local.sql' % PROJECT_NAME))
    local('mkdir -p sql')
    local('pg_dump --no-owner --no-acl %s_dev > sql/db_dump_local.sql' % PROJECT_NAME)


def dump_remotedb():
    """
    Dumps remote prod database
    """
    print(yellow('==> dumping remote database %s -> sql/db_dump_remote.sql' % PROJECT_NAME))
    with cd(env.path):
        sudo('mkdir -p sql', user=env.project_user)
        sudo('pg_dump --no-owner --no-acl %s_prod > sql/db_dump_remote.sql' % PROJECT_NAME, user=env.project_user)


def upload_db():
    """
    Uploads db
    """
    print(yellow('==> uploading sql folder to remote'))
    put('sql', '%s' % env.path, use_sudo=True)
    print(yellow('==> chowning database folder'))
    _setowner(os.path.join(env.path, 'sql'))
    print(yellow('==> chmoding database folder'))
    _setperms('775', os.path.join(env.path, 'sql'))


def download_db():
    """
    Downloads db
    """
    print(yellow('==> downloading sql file from remote'))
    with cd(env.path):
        get('sql/db_dump_remote.sql', 'sql/db_dump_remote.sql')


def load_db_remote():
    """
    Loads db on remote
    """
    if _exists(os.path.join(env.path, 'sql')):
        print(yellow('==> loading database on remote'))
        result = sudo('psql %s < %s' % (env.db_name, os.path.join(env.path, 'sql/db_dump_local.sql')), user='postgres')

        if result.failed:
            if 'already exists' in result:
                print(red('==> error: database already exists'))


def load_db_local():
    """
    Loads remote db on local dev
    """
    if not confirm("This will drop the local dev database and import the remote database. Are you sure about this?"):
        abort("Aborting")

    print(yellow('==> dropping local db'))
    with settings(warn_only=True):
        result = local('dropdb %s_dev' % env.project_name)
        if result.failed:
            if 'does not exist':
                print(yellow('==> already dropped'))
            else:
                print(red('==> error when dropping db'))
                raise SystemExit()

    print(yellow('==> creating new local dev database'))
    local('psql -c "CREATE DATABASE %s_dev ENCODING \'UTF-8\';" -U postgres' % (env.project_name))

    result = local('psql %s_dev < %s' % (env.project_name, 'sql/db_dump_remote.sql'))

    if result.failed:
        if 'already exists' in result:
            print(red('==> error: database already exists'))


def dump_local_db_and_load_db_on_remote():
    """
    Mirrors local dev db to target
    """
    dump_localdb()
    upload_db()
    load_db_remote()
    grant_db()


def dump_remote_db_and_load_db_on_local():
    """
    Mirrors remote db to local dev
    """
    dump_remotedb()
    download_db()
    load_db_local()


def mirror_prod():
    """
    Mirrors remote media/ and database to local
    """
    download_media()
    dump_remote_db_and_load_db_on_local()


def showconfig():
    """
    Prints out the config
    """
    require('hosts')
    import pprint
    pp = pprint.PrettyPrinter(indent=4)
    pp.pprint(env)


def upload_media():
    """
    Uploads media
    """
    if not _exists(os.path.join(env.path, 'media')):
        print(yellow('==> uploading local media folder to remote'))
        put('media', '%s' % env.path, use_sudo=True)
        print(yellow('==> chowning remote media folder'))
        _setowner(os.path.join(env.path, 'media'))
        print(yellow('==> chmoding remote media folder'))
        _setperms('755', os.path.join(env.path, 'media'))


def download_media():
    """
    Download media/ from remote
    """
    print(yellow('==> downloading remote media folder'))
    get(os.path.join(env.path, 'media'), '.')


def upload_etc():
    """
    Uploads etc
    """
    print(yellow('==> uploading etc folder'))
    put('etc', '%s' % env.path, use_sudo=True)
    print(yellow('==> chowning etc folder'))
    _setowner(os.path.join(env.path, 'etc'))
    print(yellow('==> chmoding etc folder'))
    _setperms('755', os.path.join(env.path, 'etc'))
    _set_logrotate_perms()


def _warn(str):
    """
    Outputs a warning formatted str
    """
    print(red('-- WARNING ---------------------------------------'))
    print(red(str))
    print(red('-- WARNING ---------------------------------------'))


def restart():
    """
    Restarts the server process through supervisorctl
    """
    require('hosts')
    with cd(env.path):
        print(yellow('==> restarting remote server process'))
        sudo('supervisorctl restart %s' % env.procname)


def stop():
    """
    Stops the server process through supervisorctl
    """
    require('hosts')
    with cd(env.path):
        print(yellow('==> stopping remote server process'))
        sudo('supervisorctl stop %s' % env.procname)


def start():
    """
    Starts the server process through supervisorctl
    """
    require('hosts')
    with cd(env.path):
        print(yellow('==> starting remote server process'))
        sudo('supervisorctl start %s' % env.procname)


def _setperms(perms, path):
    """
    chmods path to perms, recursively
    """
    if not perms:
        abort('_setperms: not enough arguments. perms=%s, path=%s' % (perms, path))
    if not path:
        abort('_setperms: not enough arguments. perms=%s, path=%s' % (perms, path))

    require('hosts')
    print(yellow('==> setting %s on %s [recursively]' % (perms, path)))
    sudo('chmod -R %s "%s"' % (perms, path))


def _setowner(path=''):
    """
    chowns provided path to project_user:project_group
    """
    if not path:
        abort('_setowner: cannot be empty')
    require('hosts')
    print(yellow('==> owning %s [recursively]' % path))
    sudo('chown %s:%s -R "%s"' % (env.project_user, env.project_group, path))


def nukemedia():
    """
    Deletes media path recursively on host, then recreates
    directory and sets perms
    """
    require('hosts')
    print(red('-- WARNING ---------------------------------------'))
    print(red('You are about to delete %s from the remote server.' % env.media_path))
    print(red('command: rm -rf %s' % env.media_path))
    print(red('-- WARNING ---------------------------------------'))
    _confirmtask()
    print(yellow('==> ok, nuking files.'))
    sudo('rm -rf %s' % env.media_path)
    print(yellow('==> recreating media directory'))
    sudo('mkdir -p %s' % env.media_path, user=env.project_user)
    _setowner(env.media_path)
    _setperms('g+w', env.media_path)


WORDLIST_PATHS = [os.path.join('/', 'usr', 'share', 'dict', 'words')]
DEFAULT_MESSAGE = "Are you sure you want to do this?"
WORD_PROMPT = '  [%d/%d] Type "%s" to continue (^C quits): '


def _confirmtask(msg=DEFAULT_MESSAGE, horror_rating=1):
    """Prompt the user to enter random words to prevent doing something stupid."""

    valid_wordlist_paths = [wp for wp in WORDLIST_PATHS if os.path.exists(wp)]

    if not valid_wordlist_paths:
        abort('No wordlists found!')

    with open(valid_wordlist_paths[0]) as wordlist_file:
        words = wordlist_file.readlines()

    print msg

    for i in range(int(horror_rating)):
        word = words[random.randint(0, len(words))].strip()
        p_msg = WORD_PROMPT % (i + 1, horror_rating, word)
        answer = prompt(p_msg, validate=r'^%s$' % word)


def fixprojectperms():
    """
    Chowns the project directory to project_user:project_group
    """
    require('hosts')
    _setowner(env.path)

    with settings(warn_only=True):
        _set_logrotate_perms()
        _set_logdir_perms()
        _set_media_perms()


def _success():
    print(green('==> all tasks successfully finished!'))


def supervisorcfg():
    """
    Links our supervisor config file to the config.d dir
    """
    require('hosts')
    print(yellow('==> linking supervisor config file to conf.d/'))
    if not _exists('/etc/supervisor/conf.d/%s.conf' % (env.procname)):
        sudo('ln -s %s/etc/supervisord/%s.conf /etc/supervisor/conf.d/%s.conf' % (env.path, env.flavor, env.procname))
    else:
        print(red('==> supervisorcfg %s.conf already exists' % (env.procname)))

    print(yellow('==> rereading and updating through supervisorctl'))
    sudo('supervisorctl reread')
    sudo('supervisorctl update')


def taillogs():
    """
    Show latest 100 lines of application log
    """
    sudo('tail -n 100 %s' % (os.path.join(env.path, "log", "%s.log" % env.project_name)))


def nginxcfg():
    """
    Links our nginx config to the sites-enabled dir
    """
    require('hosts')
    print(yellow('==> linking nginx config file to conf.d/'))
    if not _exists('/etc/nginx/sites-enabled/%s' % (env.procname)):
        sudo('ln -s %s/etc/nginx/%s.conf /etc/nginx/sites-enabled/%s' % (env.path, env.flavor, env.procname))
    else:
        print(red('==> nginx config %s already exists' % env.procname))
    print(yellow('==> make sure our nginx log directory exists!'))
    if not _exists('%s/log/nginx' % env.path):
        sudo('mkdir -p %s/log/nginx' % env.path, user=env.project_user)
    else:
        print(red('==> %s/log/nginx already exists!' % (env.path)))

    nginxreload()


def logrotatecfg():
    """
    Links our logrotate config file to the config.d dir
    """
    require('hosts')
    logrotate_src = "%s/etc/logrotate/%s.conf" % (env.path, env.flavor)
    print(yellow('==> linking logrotate config file to /etc/logrotate.d/'))
    if not _exists('/etc/logrotate.d/%s.conf' % (env.procname)):
        sudo('ln -s %s /etc/logrotate.d/%s.conf' % (logrotate_src, env.procname))
    else:
        print(red('==> logrotate %s.conf already exists!' % (env.procname)))

    _set_logrotate_perms()


def _set_logrotate_perms():
    logrotate_src = "%s/etc/logrotate/%s.conf" % (env.path, env.flavor)
    # set permission to 644
    print(yellow('==> chmoding logrotate conf to 644'))
    sudo('chmod 644 "%s"' % logrotate_src)

    # set owner to root
    print(yellow('==> chowning logrotate to root'))
    sudo('chown root:web "%s"' % logrotate_src)


def _set_logdir_perms():
    print(yellow('==> chmoding log directory to 755'))
    _setperms('755', os.path.join(env.path, 'log'))


def _set_media_perms():
    print(yellow('==> chmoding media directory to 755'))
    _setperms('755', os.path.join(env.path, 'media'))


def createuser():
    """
    Creates a linux user on host, if it doesn't already exists
    and adds is to configured group
    """
    require('hosts')
    print(yellow('==> creating user %s on remote' % env.project_user))
    with _settings(warn_only=True):
        output = sudo('id %s' % env.project_user)
        if output.failed:
            # no such user, create it.
            sudo('adduser %s' % env.project_user)
            # create group
            sudo('groupadd -f %s' % env.project_group)
            # add to group
            sudo('usermod -a -G %s %s' % (env.project_group, env.project_user))
            output = sudo('id %s' % env.project_user)
            if output.failed:
                abort('==> error: could not create user!')
        else:
            print(red('==> user %s already exists.' % env.project_user))
        print(yellow('==> adding %s to group %s' % (env.project_user, env.project_group)))
        sudo('usermod -a -G %s %s' % (env.project_group, env.project_user))


def createdb():
    """
    Creates pgsql role and database
    """
    require('hosts')
    with _settings(warn_only=True):
        print(yellow('==> creating database user %s' % env.db_user))
        result = sudo('psql -c "CREATE USER %s WITH NOCREATEDB NOCREATEUSER ENCRYPTED PASSWORD \'%s\';"' % (env.db_user, env.db_pass), user='postgres')
        if result.failed:
            if 'already exists' in result:
                print(red('==> database user %s already exists' % env.db_user))
            else:
                abort(red('==> error in database user creation!'))

        print(yellow('==> creating database %s with owner %s' % (env.db_name, env.db_user)))
        result = sudo('psql -c "CREATE DATABASE %s WITH OWNER %s ENCODING \'UTF-8\'";' % (
            env.db_name, env.db_user), user='postgres')

        if result.failed:
            if 'already exists' in result:
                print(red('==> database %s already exists' % env.db_name))
            else:
                abort(red('==> error when creating database %s' % env.db_name))


def nginxreload():
    """
    Reloads nginxs configuration
    """
    print(yellow('==> reloading nginx configuration'))
    sudo('/etc/init.d/nginx reload')


def nginxrestart():
    """
    Restarts nginxs configuration
    """
    print(yellow('==> restarting nginx'))
    sudo('/etc/init.d/nginx restart')


def _notify_build_complete(version):
    local('terminal-notifier -message "Release process completed!" -title %s -subtitle v%s -sound default -group %s -open %s' % (
        PROJECT_NAME, version, PROJECT_NAME, PROD_URL))


def create_acme_dir():
    sudo('mkdir -p %s/acme-challenge/.well-known' % env.path, user=env.project_user)
    _setowner(os.path.join(env.path, 'acme-challenge/.well-known'))
