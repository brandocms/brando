- The admin builds on Node 24: the generated backend's `engines` is `>=24.0.0` and the Dockerfile's
  asset stages use `node:24` ([#3189](https://github.com/brandocms/brando/pull/3189)).
  Install Node 24, and run `mix brando.gen.backend --upgrade` to update the Dockerfile.
