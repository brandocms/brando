- An application with Blueprints migrates an empty database again, past `brando_53`
  ([#3236](https://github.com/brandocms/brando/pull/3236)).
  Rewrite migration copies installed earlier with `mix brando.gen.migrations --refresh`.

- A fresh install's `create_pages` migration no longer warns that
  `Brando.Villain.Migration.villain/0` is deprecated
  ([#3236](https://github.com/brandocms/brando/pull/3236)).
