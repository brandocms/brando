- Generated pages and error pages end clear of the footer, and the footer reaches the bottom of a
  short page ([#3238](https://github.com/brandocms/brando/pull/3238)).
  In an existing site, add `main > .page-section:last-child { @space padding-bottom xl; }`,
  `flex-grow: 1;` on `main`, and `@display flex/column/nowrap; min-height: 100dvh;` on `body`.

- `mix brando.install` ignores all of `priv/static`
  ([#3238](https://github.com/brandocms/brando/pull/3238)).
