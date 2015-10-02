## v0.2.0-dev (2015-XX-XX)
* Enhancements
  * Additional custom stylesheet option for admin. 
    SCSS for this is stored in `web/static/css/brando.custom.scss`, and compiled to `priv/static/css/brando.custom.css`.
  * Optional `admin_hostname` plug to check `conn.host` has `admin` prefix. 
    This is to make sure the admin area is only accessed from `admin.myapp.com`

* Bug fixes
  * Fixed css bugs on system info page.

## v0.1.0 (2015-09-28)

* Initial release.