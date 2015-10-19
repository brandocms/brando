## v0.5.0-dev (2015-XX-XX)

* Enhancements
  * Moved to gettext. Adds norwegian translations.
  * Added `put_css_classes/2` to `Brando.Plug.HTML`. Adds classes to your body tag. `mix ecto.migrate` to add field to `pages` table.
  * Clean out old image and sizes when uploading a new image w/Imagefield

* Bug fixes
  * Fixes bug in `brando.gen.html` where admin's update action would be broken.
  * Fixes a ton of small snags in `brando.gen.html`.

* Backwards incompatible changes
  * Moved `put_section/2` from `Brando.Plug.Section` to `Brando.Plug.HTML`. Fix imports accordingly.
  * Changed `menu` format. Now, you must set `:name` in the map instead of its own argument. `menu %{name: "blah"}`
  * Norwegian language is now `nb` instead of `no`. Update your `brando.exs` and your `users` table in your database.
  * `use Brando.Villain.Model` -> `use Brando.Villain, :model`
  * `use Brando.Villain.Migration` -> `use Brando.Villain, :migration`
  * `use Brando.Villain.Controller` -> `use Brando.Villain, [:controller, [.]]`

## v0.4.0 (2015-10-15)

* Enhancements
  * Add a delay to login attempts to stifle brute force attempts *some*.
  * Recreate images when an image series cfg changes.
  * Page cloning: remove key/name/slug to prevent accidental dupes. Also doesn't automatically store new page, but presents an editing form instead.
  * Sort child pages by key.

* Bug fixes
  * Fixed generators erroring out on "unknown application".

* Backwards incompatible changes
  * Renamed `User.has_role?/2` to `User.role?/2`

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