- `mix brando.migrate54` rewrites navigation item reads (`item.url`, `item.title`,
  `item.open_in_new_window`, `item.items`) to the `Brando.HTML` menu item helpers and
  `item.children` ([#3167](https://github.com/brandocms/brando/pull/3167)).
  Run `mix format` afterwards.
