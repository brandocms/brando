- **The admin builds on Node 24** (#3187). The generated backend's and
  BrandoJS's `engines` is `>=24.0.0`, so pnpm refuses Node 22 and older; the
  template and E2E Dockerfiles' asset stages are `node:24`, and
  `mix brando.gen.backend --upgrade` writes them. Brando's `.mise.toml` and CI
  use Node 24.22, and `mix brando.doctor` and `scripts/prepare_055_deps.exs`
  advise Node 24.
