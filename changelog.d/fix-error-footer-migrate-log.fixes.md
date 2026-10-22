- 404 and 500 pages show the site's footer ([#3239](https://github.com/brandocms/brando/pull/3239)).

- A release migrating an empty database logs every migration
  ([#3239](https://github.com/brandocms/brando/pull/3239)).
  In an existing `ReleaseTasks`, add the `:logger.update_handler_config/3` line from the template to
  `load_app/0`.
