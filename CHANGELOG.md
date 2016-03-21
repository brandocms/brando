## v0.27.0-dev (2016-XX-XX)

## v0.26.0 (2016-03-22)

* Enhancements
  * Clean up system info overview.

* Bug fixes
  * Add notice in README about socket_options. Add this to prod.secret.exs to prevent
    memory usage ballooning:

    ```diff
      config :my_app, MyApp.Repo,
        adapter: Ecto.Adapters.Postgres,
        username: "my_app",
        password: "my_password",
        database: "my_app_prod",
        extensions: [{Postgrex.Extensions.JSON, library: Poison}],
    +   socket_options: [recbuf: 8192, sndbuf: 8192],
        pool_size: 20
    ```
  * Fix EXRM defaults.
  * Cookie law cleanup. Remove HR and extraneous wrapper. Clean up defaults.
  * Move log directory to log/ from logs/

## v0.25.0 (2016-03-16)

* Enhancements
  * Add docker building and deployment! Copy over the new `etc/` directory,
    `Dockerfile` and `.dockerignore`, the new `fabfile.py` + `lib/*` from
    `templates/brando.install` to get started.

## v0.24.0 (2016-03-07)

* Backwards incompatible changes
  * Ecto 2 now expects `%{}` instead of `:invalid` in `cast`.

* Enhancements
  * Added password protection to lockdown. Set with `:lockdown_password` in `config/brando.exs`.
  * Updated for Ecto v2.0.0-beta2
  * Moved from blacksmith to ex_machina
  * Cleaned up tests

## v0.23.0 (2016-03-05)

* Enhancements
  * Villain: add html and markdown blocks. Add these to your parser if you want to use them,
    look at Brando's default parser for an example implementation.

* Bug fixes
  * Fixed searcher.js init bug
  * Fixed fabfile deployment bugs
  * Fixed brunch template not compiling css
  * Fixed supervisord templates

## v0.22.1 (2016-02-27)

* Enhancements
  * Updated gettext req to 0.10 and relaxed requirement.
  * Fix mix.exs template typo.
  * Add missing deps to mix.exs template
  * Install pre-made package.json to otp project.

## v0.22.0 (2016-02-26)

* Bug fixes
  * Fixed bug with Ecto 2.0 tags. Now accepts :invalid, :empty and empty map.
  * Fixed bug where all errors are shown on new form.
  * Update model template to Ecto 2.0

## v0.21.0 (2016-02-25)

* Backwards incompatible changes
  * Extracted Instagram to its own application -> http://www.github.com/twined/brando_instagram
  * Updated to run on Ecto v2.0. Your otp app needs
    `{:phoenix_ecto, "~> 3.0.0-beta"}` in mix.exs deps (or 3.0.0 when it's out.)
  * form/4 expects `schema` keyword instead of `model`
  * model_name renamed to schema_name
  * model_repr renamed to schema_repr

## v0.20.0 (2016-02-17)

* Enhancements/backwards incompatible changes
  * Extra modules now have to register through `Brando.Registry.register(MyApp.Module)`. You can supply what you wish to register as options. `[:menu, :gettext]` are the defaults.
  * This means you can remove the `Brando.Menu` config in `brando.exs`

* Enhancements
  * Added `Brando.Registry.wipe` to clear out registry for use in testing.

* Enhancements
  * Sequence's filter functions now accepts Ecto Queryables.

## v0.19.0 (2016-02-13)

* Backwards incompatible changes
  * Extracted Pages to its own application -> http://www.github.com/twined/brando_pages

## v0.18.0 (2016-02-12)

* Backwards incompatible changes
  * Extracted News to its own application -> http://github.com/twined/brando_news
  * `delete_original_and_sized_images` now takes two arguments. The model, and an :atom representation of the field. Instead of `delete_original_and_sized_images(post.cover)` you do `delete_original_and_sized_images(post, :cover)`.
  * Renamed route imports:

        Brando.Routes.Admin.Analytics -> Brando.Analytics.Routes.Admin
        Brando.Routes.Admin.Dashboard -> Brando.Dashboard.Routes.Admin
        Brando.Routes.Admin.Images    -> Brando.Images.Routes.Admin
        Brando.Routes.Admin.Instagram -> Brando.Instagram.Routes.Admin
        Brando.Routes.Admin.News      -> Brando.News.Routes.Admin
        Brando.Routes.Admin.Pages     -> Brando.Pages.Routes.Admin
        Brando.Routes.Admin.Users     -> Brando.Users.Routes.Admin

   * Renamed menus:

        Brando.Menu.Admin     -> Brando.Admin.Menu
        Brando.Menu.Analytics -> Brando.Analytics.Menu
        Brando.Menu.Images    -> Brando.Images.Menu
        Brando.Menu.Instagram -> Brando.Instagram.Menu
        Brando.Menu.News      -> Brando.News.Menu
        Brando.Menu.Pages     -> Brando.Pages.Menu
        Brando.Menu.Users     -> Brando.Users.Menu

* Bug fixes
  * Fix accordion bug where opening a page with a hash would not work.

* Enhancements
  * Add seed task to default fabric deployment script.

## v0.17.0 (2016-02-08)

* Enhancements/backwards incompatible changes
  * Changed javascript packing. See Brando's `priv/templates/brando.install/brunch_config.js` on github for new format.
  * Pull in brando scripts and brando_villain through NPM.
  * Add to your `package.json`'s dependencies:

      "brando": "file:deps/brando",
      "brando_villain": "file:deps/brando_villain"

  * Add to your `mix.exs`:

      {:brando_villain, github: "twined/brando_villain"}

* Bug fixes
  * Fixed Dropzone not being included in JS bundle

* Enhancements
  * Pull in bootstrap-sass to `app.scss`.
  * Cleaned up brunch-config

## v0.16.0 (2016-01-31)

* Enhancements
  * Moved to brunch's new NPM system in app templates. This means you have to change your `brunch-config.js` paths to `'node_modules/phoenix/priv/static/phoenix.js'`. You also have to change `app.js` imports to `import {Socket} from "phoenix"` and `import "phoenix_html"`. Add to `package.json` under `dependencies`: `"phoenix": "file:deps/phoenix"` and `"phoenix_html": "file:deps/phoenix_html"`.
  * Add dummy custom admin script to application template

* Bug fixes
  * Fix outdated Villain instructions.

## v0.15.0 (2016-01-18)

* Enhancements
  * Added `Brando.Social.Email` for sharing current page URL through email.
  * Improve default Villain parser for text blocks.
  * Use `default_language` config with `render_fragment` instead of hardcoded english.
  * Set `auth_sleep_duration` config setting fallback to 2500 ms, and remove from default `brando.exs`.

## v0.14.0 (2016-01-13)

* Enhancements
  * Added `Brando.HTML.active(@conn, path)`. Returns `active` if `@conn`'s full path matches `path`.
  * Added ability to pass `:original` to `Brando.Utils.img_url` to retrieve the image's original path.

* Bug fixes
  * Fixed not setting otp app's backend translation language. Add `plug :put_admin_locale, MyApp.Backend.Gettext` to your `admin` pipeline in `router.ex`.
  * Fixed some access bugs for Elixir v1.2.
  * Fixed default errors on "new" image_serie form.
  * Fixed brunch compilation warnings on a new brando installation.
  * Changed `gettext` config location to `web/gettext.ex` so that we overwrite Phoenix's default file.
  * Fixed `compile` script to compile after building production assets. Previously, the assets were not copied to `_build` directory due to compiling project before the new assets were built.
  * Fixed typo in `brando.exs` config

## v0.13.0 (2015-12-17)

* Bug fixes
  * Fixed bug in `tablize` where the dropdown links were broken.

* Backwards incompatible changes
  * Ecto 1.1 removes callbacks: This means that every model that uses `Brando.Villain, :model` needs to implement `generate_html/1` in its `changeset` functions. This function is provided by the use macro.
  * Ecto 1.1 removes callbacks: This means that every model that uses `Brando.Field.ImageField` needs to implement `cleanup_old_images/1` in its `changeset` functions. This function is provided by the use macro.
  * Ecto 1.1 deprecates `Ecto.Model`. Use `Ecto.Schema` instead.
  * Removed localization prompts from `brando.gen.html`. Handle the model translations through gettext instead.

## v0.12.0 (2015-12-06)

* Enhancements
  * Removed `:http_lib` configs, and use sane defaults instead. It's only changed for testing purposes anyway.
  * Add `:use_token` to Instagram. Retrieves an access token from Instagram's API. This is needed for API clients registered after November 2015. This option requires you set a `:username` and `:password` as well.

* Backwards incompatible changes
  * Add `:otp_app` config option to brando.exs. This is required for accessing the otp app's priv dir. `config :brando, otp_app: :my_app`
  * Renamed `Brando.Instagram`'s `fetch` to `query`. Both function and configuration keyword.

## v0.11.0 (2015-11-17)

* Bug fixes
  * Fix `can_login?`. Now dumps value properly before checking.

* Backwards incompatible changes
  * Removed `:instagram_start` from system info page and controller.
  * Added `log_dir` to brando.exs. Default is `Path.Expand('./logs)`
  * Removed `Brando.Page.duplicate/2`. We duplicate through the controller instead.
  * Added `config/brando.exs`: `Brando.Instagram` - `http_lib` for testing purposes. You need to provide this. Default should be `Brando.Instagram.API`.
  * Changed `Brando.Pages.Utils.get_fragment`. Now must have language passed to it: `get_fragment("my/fragment", Gettext.get_locale(MyApp.Gettext))` or `get_fragment("my/fragment", "en")`. If no language is passed, "en" will be used as default
  * Deprecated `Brando.Utils.get_page_title` when `title` is a map. Use Gettext instead.

## v0.10.0 (2015-11-11)

* Enhancements
  * Cleaned up assets. Ditched gulp and moved to brunch.

* Backwards incompatible changes
  * Updated for Gettext 0.7.0. Check that your `router.ex`'s `put_locale` plug receives your Gettext module. I.e: `plug put_locale, MyApp.Gettext`


## v0.9.0 (2015-11-08)

* Enhancements
  * Adds analytics through `Eightyfour`. See `Brando.Analytics` docs for more information.

* Backwards incompatible changes
  * Changed how Brando.Instagram is started. Should now be added as a `worker` to your OTP app's supervision tree: `worker(Brando.Instagram, [])`. You can also remove the naming from brando.exs, since it is no longer used. See `Brando.Instagram` docs for more information.

## v0.8.0 (2015-11-02)

* Enhancements
  * Add forced Villain re-rendering for news posts.

* Bug fixes
  * Remove `Mix.env` calls to make Brando work in releases.
  * Make `Brando.version` not depend on Mix
  * Add `css_classes` field to page migrations

## v0.7.0 (2015-10-24)

* Enhancements
  * When installing, copy static to `web/static/assets` and let brunch copy files for us. This allows us to just nuke the `priv/static` directory and `brunch build --production`. We can also remove it from git.
  * Adds `compile` script for compiling prod and building assets.

* Bug fixes
  * Supervisord prod config: now autostarts on boot.

## v0.6.0 (2015-10-21)

* Enhancements
  * Adds `Brando.Pages.Utils.render_fragment/1`
  * Add alert when status change is successful on instagram admin.
  * Add translations for upload errors

* Bug fixes
  * Fix villain upload bug
  * Fix translation error in image index

## v0.5.0 (2015-10-19)

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
