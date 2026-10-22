- `mix brando.doctor` and `mix brando.migrate55` warn when `assets/backend` is not on the native
  EuropaCSS packages Brando pins ([#3190](https://github.com/brandocms/brando/pull/3190)).
  Fix it with `mix brando.gen.backend --upgrade` and `mix brando.assets.setup --backend-only`, or
  `pnpm install`.
