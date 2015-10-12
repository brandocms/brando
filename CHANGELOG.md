## v0.3.0 (2015-10-12)

* Enhancements
  * Add last lines of supervisor log to system info pane. Only shows for superusers.
  * Automatically update brando/villain static through brunch. 
    See our updated `brunch-config.js`.

* Bug fixes
  * Fixed logrotate permissions bug in fabfile.

## v0.2.0 (2015-10-04)

* Enhancements
  * Additional custom stylesheet option for admin. 
    SCSS for this is stored in `web/static/css/brando.custom.scss`, and compiled to `priv/static/css/brando.custom.css`.
  * Optional `admin_hostname` plug to check `conn.host` has `admin` prefix. 
    This is to make sure the admin area is only accessed from `admin.myapp.com`
  * Added forced re-rendering of all pages through Villain parser.

* Bug fixes
  * Fixed css bugs on system info page.

## v0.1.0 (2015-09-28)

* Initial release.