- `mix brando.setup --no-demo` (and `mix brando.gen.seeds --no-demo`) seeds identity, SEO, the main menu, an empty homepage and an empty footer fragment, without the `brando-default-*` demo modules.

- `mix brando.seeds.remove_defaults` lists what still uses the seeded `brando-default-*` modules, and with `--yes` moves the unused ones, and the homepage and footer still as seeded, to the trash; in a release, `bin/my_app rpc "Brando.Setup.Seeds.remove_defaults(yes: true)"`.
