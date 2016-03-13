#!/usr/bin/env python
import os
import random
import re

from datetime import datetime
from fabric.api import *
from fabric.contrib.files import exists as _exists
from fabric.context_managers import settings as _settings
from fabric.colors import red, green, yellow, cyan, blue
from fabric.operations import prompt
from fabric.utils import abort

VERSION_NUMBER = '2.0.0'

#
# Project-specific setup.

PROJECT_NAME = '<%= application_name %>'
DB_PASS = 'prod_database_password'

SSH_USER = 'username'
SSH_PASS = 'sudoer_pass'
SSH_HOST = 'host.net'
SSH_PORT = 30000

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


def _get_version():
    return VERSION_NUMBER

print "-------------------------------------------------------------"
print blue('& brando deployment script v%s | copyright twined 2010-%s'
           % (_get_version(), datetime.now().year))
print "-------------------------------------------------------------"
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


def bootstrap():
    """
    Bootstraps and provisions project on host
    """
    require('hosts')
    _warn('''
        This is a potientially dangerous operation. Make sure you have\r\n
        all your ducks in a row, and that you have checked the configuration\r\n
        files both in conf/ and in the fabfile.py itself!
    ''')
    _confirmtask()
    createuser()
    deploy()
    upload_secrets()
    installreqs()
    createdb()
    supervisorcfg()
    nginxcfg()
    logrotatecfg()
    migrate()
    gitpull()
    compile()
    npm_install()
    build_static()
    restart()
    _success()


def bootstrap_release(version):
    """
    Bootstraps and provisions project RELEASE on host
    """
    require('hosts')
    _warn('''
        This is a potientially dangerous operation. Make sure you have\r\n
        all your ducks in a row, and that you have checked the configuration\r\n
        files both in conf/ and in the fabfile.py itself!
    ''')
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

    dump_and_load_db()

    restart()
    _success()


def deploy_release(version):
    """
    Build release with docker, copy release, upload release, unpack release and restart.
    Ex: fab prod deploy_release:0.1.0
    """
    build_release()
    copy_release_from_docker(version)
    upload_release(version)
    unpack_release(version)
    restart()


def _docker_env():
    """
    Sets the environment to use default docker
    """
    _env = local('docker-machine env default', capture=True)
    # Reorganize into a string that could be used with prefix().
    _env = re.sub(r'^#.*$', '', _env, flags=re.MULTILINE)  # Remove comments
    _env = re.sub(r'^export ', '', _env, flags=re.MULTILINE)  # Remove `export `
    _env = re.sub(r'\n', ' ', _env, flags=re.MULTILINE)  # Merge to a single line
    return _env


def build_release():
    """
    Build release with docker
    """
    with prefix(_docker_env()):
        local('docker build -t twined/%s .' % env.project_name)


def copy_release_from_docker(version):
    local('mkdir -p prod_rel')
    with prefix(_docker_env()):
        local('docker run --rm --entrypoint cat twined/%s /app/rel/%s/releases/%s/%s.tar.gz > prod_rel/%s_%s.tar.gz' % (env.project_name, env.project_name, version, env.project_name, env.project_name, version))


def upload_release(version):
    """
    Upload release to target
    """
    print(cyan('-- uploading release to target host'))
    put('prod_rel/%s_%s.tar.gz' % (env.project_name, version), '%s' % env.path, use_sudo=True)
    print(cyan('-- chowing archive'))
    _setowner(os.path.join(env.path, '%s_%s.tar.gz' % (env.project_name, version)))
    print(cyan('-- chmoding archive'))
    _setperms('660', os.path.join(env.path, '%s_%s.tar.gz' % (env.project_name, version)))


def unpack_release(version):
    """
    Unpack release at target and delete archive
    """
    with cd(env.path), shell_env(HOME='/home/%s' % env.project_user):
        print(cyan('-- unpacking release'))
        sudo('tar xvf %s_%s.tar.gz' % (env.project_name, version), user=env.project_user)
        print(cyan('-- removing archive'))
        sudo('rm %s_%s.tar.gz' % (env.project_name, version), user=env.project_user)

    fixprojectperms()


def grant_db():
    """
    Grant all privileges on remote database to project user
    """
    require('hosts')
    with _settings(warn_only=True):
        print(cyan('-- grant_db // granting privs to user %s' % env.db_user))
        sudo('psql -c "grant all privileges on database %s to %s;"' % (env.db_name, env.db_user), user='postgres')
        sudo('for tbl in `psql -qAt -c "select tablename from pg_tables where schemaname = \'public\';" %s` ; do  psql -c "alter table \"$tbl\" owner to %s" %s ; done' % (env.db_name, env.db_user, env.db_name), user='postgres')
        sudo('for tbl in `psql -qAt -c "select sequence_name from information_schema.sequences where sequence_schema = \'public\';" %s` ; do  psql -c "alter table \"$tbl\" owner to %s" %s ; done' % (env.db_name, env.db_user, env.db_name), user='postgres')
        sudo('for tbl in `psql -qAt -c "select table_name from information_schema.views where table_schema = \'public\';" %s` ; do  psql -c "alter table \"$tbl\" owner to %s" %s ; done' % (env.db_name, env.db_user, env.db_name), user='postgres')


def ensure_log_directory_exists():
    """
    Check and ensure log/ exists on remote
    """
    require('hosts')
    if not _exists(os.path.join(env.path, "log")):
        print(cyan('-- creating %s/log as %s' % (env.path, env.project_user)))
        sudo('mkdir -p %s/log' % env.path, user=env.project_user)

    fixprojectperms()


def create_path():
    """
    Create deployment path on remote
    """
    require('hosts')
    if not _exists(env.project_base):
        sudo('mkdir -p %s' % env.project_base)
        sudo('chown %s:%s -R "%s"' % (SSH_USER, env.project_group, env.project_base))
        _setperms('g+w', env.project_base)

    if not _exists(env.path):
        print(cyan('-- creating %s as %s' % (env.path, env.project_user)))
        sudo('mkdir -p %s' % env.path, user=env.project_user)

    fixprojectperms()


def migrate_release():
    """
    Run database migrations for release
    """
    require('hosts')
    print(cyan('-- migrate // running db migrations for release'))
    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user):
        sudo('bin/%s escript bin/release_tasks.escript migrate' % env.project_name,
             user=env.project_user)


def deploy():
    """
    Clone the git repository to the correct directory
    """
    require('hosts')
    if not _exists(env.path):
        print(cyan('-- creating %s as %s' % (env.path, env.project_user)))
        sudo('mkdir -p %s' % env.path, user=env.project_user)
        with cd(env.path):
            if (getattr(env, 'branch', '') == ''):
                print(cyan('-- git // cloning source code into %s' % env.path))
                sudo('git clone file:///code/git/%s .' % env.repo, user=env.project_user)
            else:
                print(cyan('-- git // cloning source code branch %s into %s' % (env.branch, env.path)))
                sudo('git clone file:///code/git/%s -b %s .' % (env.repo, env.branch), user=env.project_user)
        fixprojectperms()
    else:
        print(cyan('-- directory %s exists, skipping git clone & updating instead' % env.path))
        gitpull()


def dump_localdb():
    """
    Dumps local _dev database
    """
    local('mkdir -p sql')
    local('pg_dump --no-owner --no-acl %s_dev > sql/db_dump.sql' % PROJECT_NAME)


def upload_db():
    """
    Uploads db
    """
    print(cyan('-- upload_db // uploading sql folder'))
    put('sql', '%s' % env.path, use_sudo=True)
    print(cyan('-- upload_db // chowning...'))
    _setowner(os.path.join(env.path, 'sql'))
    print(cyan('-- upload_db // chmoding'))
    _setperms('775', os.path.join(env.path, 'sql'))


def load_db():
    """
    Loads db on remote
    """
    if _exists(os.path.join(env.path, 'sql')):
        # psql dbname < infile
        result = sudo('psql %s < %s' % (env.db_name, os.path.join(env.path, 'sql/db_dump.sql')), user='postgres')

        if result.failed:
            if 'already exists' in result:
                print(yellow('-- load_db // database already exists'))


def dump_and_load_db():
    """
    Mirrors local dev db to target
    """
    dump_localdb()
    upload_db()
    load_db()
    grant_db()


def showconfig():
    """
    Prints out the config
    """
    require('hosts')
    import pprint
    pp = pprint.PrettyPrinter(indent=4)
    pp.pprint(env)


def compile():
    """
    Compile project
    """
    require('hosts')
    print(cyan('-- compile // compiling project'))
    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user):
        sudo('mix compile',
             user=env.project_user)


def migrate():
    """
    Run database migrations
    """
    require('hosts')
    print(cyan('-- migrate // running db migrations'))
    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user):
        sudo('mix ecto.migrate',
             user=env.project_user)


def seed():
    """
    Run database seeding
    """
    require('hosts')
    print(cyan('-- seed // seeding db'))
    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user):
        sudo('mix run priv/repo/seeds.exs',
             user=env.project_user)


def npm_install():
    """
    Install npm packages
    """
    require('hosts')
    print(cyan('-- npm // installing deps'))
    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user):
        sudo('npm install',
             user=env.project_user)


def build_static():
    """
    Build static
    """
    require('hosts')
    print(cyan('-- npm // building static'))
    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user):
        sudo('node_modules/brunch/bin/brunch build -p',
             user=env.project_user)


def upload_media():
    """
    Uploads media
    """
    if not _exists(os.path.join(env.path, 'media')):
        print(cyan('-- upload_media // uploading media folder'))
        put('media', '%s' % env.path, use_sudo=True)
        print(cyan('-- upload_media // chowning...'))
        _setowner(os.path.join(env.path, 'media'))
        print(cyan('-- upload_media // chmoding'))
        _setperms('755', os.path.join(env.path, 'media'))


def upload_etc():
    """
    Uploads etc
    """
    if not _exists(os.path.join(env.path, 'etc')):
        print(cyan('-- upload_etc // uploading etc folder'))
        put('etc', '%s' % env.path, use_sudo=True)
        print(cyan('-- upload_etc // chowning...'))
        _setowner(os.path.join(env.path, 'etc'))
        print(cyan('-- upload_etc // chmoding'))
        _setperms('755', os.path.join(env.path, 'etc'))


def update():
    """
    Updates app with newest source code, clears caches, and restarts gunicorn
    """
    require('hosts')
    with cd(env.path):
        gitpull()
        installreqs()
        build_static()
        compile()
        fixprojectperms()
        _set_logrotate_perms()
        restart()


def upload_secrets():
    """
    Uploads secrets.cfg
    """
    print(cyan('-- upload_secrets // uploading secrets.cfg...'))
    put('config/prod.secret.exs', '%s/config/prod.secret.exs' % env.path, use_sudo=True)
    print(cyan('-- upload_secrets // chowning...'))
    _setowner(os.path.join(env.path, 'config/prod.secret.exs'))
    print(cyan('-- upload_secrets // chmoding'))
    _setperms('660', os.path.join(env.path, 'config/prod.secret.exs'))


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
        print(cyan('-- supervisor // restarting server process'))
        sudo('supervisorctl restart %s' % env.procname)


def stop():
    """
    Stops the server process through supervisorctl
    """
    require('hosts')
    with cd(env.path):
        print(cyan('-- supervisor // stopping server process'))
        sudo('supervisorctl stop %s' % env.procname)


def start():
    """
    Starts the server process through supervisorctl
    """
    require('hosts')
    with cd(env.path):
        print(cyan('-- supervisor // starting server process'))
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
    print(cyan('-- setperms // setting %s on %s [recursively]' % (perms, path)))
    sudo('chmod -R %s "%s"' % (perms, path))


def _setowner(path=''):
    """
    chowns provided path to project_user:project_group
    """
    if not path:
        abort('_setowner: cannot be empty')
    require('hosts')
    print(cyan('-- setowner // owning %s [recursively]' % path))
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
    print(cyan('-- nukemedia // ok, deleting files.'))
    sudo('rm -rf %s' % env.media_path)
    print(cyan('-- nukemedia // recreating media directory'))
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


def gitpull():
    """
    Pulls latest commit from git, and resets permissions/owners
    """
    require('hosts')
    with cd(env.path):
        print(cyan('-- git // git pull, to make sure we are still at HEAD'))
        sudo('git pull', user=env.project_user)

    fixprojectperms()


def fixprojectperms():
    """
    Chowns the project directory to project_user:project_group
    """
    require('hosts')
    _setowner(env.path)


def _success():
    print(green('----------------------------------------------------'))
    print(green('-- twined // All tasks finished!'))


def supervisorcfg():
    """
    Links our supervisor config file to the config.d dir
    """
    require('hosts')
    print(cyan('-- supervisorcfg // linking config file to conf.d/'))
    if not _exists('/etc/supervisor/conf.d/%s.conf' % (env.procname)):
        sudo('ln -s %s/etc/supervisord/%s.conf /etc/supervisor/conf.d/%s.conf' % (env.path, env.flavor, env.procname))
    else:
        print(yellow('-- supervisorcfg // %s.conf already exists!' % (env.procname)))

    sudo('supervisorctl reread')
    sudo('supervisorctl update')


def taillogs():
    sudo('tail -n 100 %s' % (os.path.join(env.path, "log", "%s.log" % env.project_name)))


def nginxcfg():
    """
    Links our nginx config to the sites-enabled dir
    """
    require('hosts')
    print(cyan('-- nginxcfg // linking config file to conf.d/'))
    if not _exists('/etc/nginx/sites-enabled/%s' % (env.procname)):
        sudo('ln -s %s/etc/nginx/%s.conf /etc/nginx/sites-enabled/%s' % (env.path, env.flavor, env.procname))
    else:
        print(yellow('-- nginxcfg // %s already exists!' % env.procname))
    print(cyan('-- nginxcfg // make sure our log directories exist!'))
    if not _exists('%s/log/nginx' % env.path):
        sudo('mkdir -p %s/log/nginx' % env.path, user=env.project_user)
    else:
        print(yellow('-- nginxcfg // %s/log already exists!' % (env.path)))

    nginxreload()


def logrotatecfg():
    """
    Links our logrotate config file to the config.d dir
    """
    require('hosts')
    logrotate_src = "%s/etc/logrotate/%s.conf" % (env.path, env.flavor)
    print(cyan('-- logrotateconf // linking config file to conf.d/'))
    if not _exists('/etc/logrotate.d/%s.conf' % (env.procname)):
        sudo('ln -s %s /etc/logrotate.d/%s.conf' % (logrotate_src, env.procname))
    else:
        print(yellow('-- logrotateconf // %s.conf already exists!' % (env.procname)))

    _set_logrotate_perms()


def _set_logrotate_perms():
    logrotate_src = "%s/etc/logrotate/%s.conf" % (env.path, env.flavor)
    # set permission to 644
    print(cyan('-- setperms // setting logrotate conf to 644'))
    sudo('chmod 644 "%s"' % logrotate_src)

    # set owner to root
    print(cyan('-- setowner // setting logrotate owner to root'))
    sudo('chown root:web "%s"' % logrotate_src)


def createuser():
    """
    Creates a linux user on host, if it doesn't already exists
    and adds is to configured group
    """
    require('hosts')
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
                abort('createuser: ERROR: could not create user!')
        else:
            print(yellow('-- createuser // user %s already exists.' % env.project_user))
        print(cyan('-- createuser // add to group'))
        sudo('usermod -a -G %s %s' % (env.project_group, env.project_user))


def createdb():
    """
    Creates pgsql role and database
    """
    require('hosts')
    with _settings(warn_only=True):
        print(cyan('-- createdb // creating user %s' % env.db_user))
        result = sudo('psql -c "CREATE USER %s WITH NOCREATEDB NOCREATEUSER ENCRYPTED PASSWORD \'%s\';"' % (env.db_user, env.db_pass), user='postgres')
        if result.failed:
            if 'already exists' in result:
                print(yellow('-- createdb // user already exists'))
            else:
                abort(red('-- createdb // error in user creation!'))

        print(cyan('-- createdb // creating db %s with owner %s' % (env.db_name, env.db_user)))
        result = sudo('psql -c "CREATE DATABASE %s WITH OWNER %s ENCODING \'UTF-8\'";' % (
            env.db_name, env.db_user), user='postgres')

        if result.failed:
            if 'already exists' in result:
                print(yellow('-- createdb // database already exists'))
            else:
                abort(red('-- createdb // error in db creation!'))


def installreqs():
    "Install required packages through hex"
    require('hosts')

    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user):
        sudo('mix do deps.get, compile', user=env.project_user)


def nginxreload():
    "Reloads nginxs configuration"
    print(cyan('-- nginx // reloading'))
    sudo('/etc/init.d/nginx reload')


def nginxrestart():
    "Restarts nginxs configuration"
    print(cyan('-- nginx // restarting'))
    sudo('/etc/init.d/nginx restart')
