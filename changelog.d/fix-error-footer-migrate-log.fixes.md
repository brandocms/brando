- **404 and 500 pages show the site's footer**. Brando's built-in 404 and the
  error pages `brando.gen.site` generates assign the `partials` fragments when
  the failing controller had not, so the layout's footer is no longer empty.

- **A release migrating an empty database logs every migration**. The
  generated `ReleaseTasks` lift the console logger's burst limit of 500 events
  a second, which dropped the last migrations' lines without saying so. An
  existing `ReleaseTasks` is kept; add the `:logger.update_handler_config/3`
  line from the template to `load_app/0` for the same.
