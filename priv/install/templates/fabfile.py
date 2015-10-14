#!/usr/bin/env python
import os
import random
from datetime import datetime
from fabric.api import *
from fabric.contrib.files import exists as _exists
from fabric.context_managers import settings as _settings
from fabric.colors import red, green, yellow, cyan, blue
from fabric.operations import prompt
from fabric.utils import abort

VERSION_NUMBER = '1.1.0'

#
# Project-specific setup.
PROJECT_NAME = 'my_app'
DB_PASS = 'password'
SSH_USER = 'username'
SSH_HOST = 'my_app.com'
SSH_PASS = 'password'

GLUE_SETTINGS = {
    'project_name': PROJECT_NAME,
    'project_group': 'web',
    'ssh_user': SSH_USER,
    'ssh_host': SSH_HOST,
    'ssh_port': 30000,
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
    collectstatic()
    gitpull()
    restart()
    _success()


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


def showconfig():
    """
    Prints out the config
    """
    require('hosts')
    import pprint
    pp = pprint.PrettyPrinter(indent=4)
    pp.pprint(env)


def migrate():
    """
    Run database migrations
    """
    require('hosts')
    print(cyan('-- migrate // running db migrations'))
    with cd(env.path), shell_env(MIX_ENV='%s' % env.flavor,
                                 HOME='/home/%s' % env.project_user,
                                 LC_ALL='nb_NO.UTF-8'):
        sudo('mix ecto.migrate' % (env.flavor),
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


def collectstatic():
    """
    Collect static for django application.
    """
    require('hosts')
    if env.flavor in ('prod', 'staging',):
        with cd(env.path):
            print '-- collectstatic // collecting static files for app'
            sudo('FLAVOR=%s %s/bin/python manage.py collectstatic --noinput' % (
                env.flavor, env.venv_path), user=env.project_user)


def update():
    """
    Updates app with newest source code, clears caches, and restarts gunicorn
    """
    require('hosts')
    with cd(env.path):
        print(cyan('-- git // git pull, to make sure we are still at HEAD'))
        sudo('git pull && MIX_ENV=%s mix deps.get && MIX_ENV=%s mix compile' % env.flavor, user=env.project_user)
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
    sudo('tail -n 100 %s' % (os.path.join(env.path, "logs", "supervisord.log")))


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
    if not _exists('%s/logs/nginx' % env.path):
        sudo('mkdir -p %s/logs/nginx' % env.path, user=env.project_user)
    else:
        print(yellow('-- nginxcfg // %s/logs already exists!' % (env.path)))

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
    sudo('chown root:wheel "%s"' % logrotate_src)


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
                                 HOME='/home/%s' % env.project_user,
                                 LC_ALL='nb_NO.UTF-8'):
        sudo('mix do deps.get, compile', user=env.project_user)


def nginxreload():
    "Reloads nginxs configuration"
    print(cyan('-- nginx // reloading'))
    sudo('/etc/init.d/nginx reload')


def nginxrestart():
    "Restarts nginxs configuration"
    print(cyan('-- nginx // restarting'))
    sudo('/etc/init.d/nginx restart')
