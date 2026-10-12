- **The 0.53 upgrade guide covers what a real site upgrade ran into.**
  `scripts/prepare_055_deps.exs` is now the recommended way to prepare
  `mix.exs`, with the hand edits as the alternative. The guide states the
  toolchain: Elixir 1.18 or newer on OTP 27 or newer (CI tests 1.18.1 on
  OTP 27.2, 1.19.5 on 28.5 and 1.20.3 on 28.4.1) and Node 22, which Brando's
  `.mise.toml` now pins as well (it pinned 24.9.0, while CI and the template
  Dockerfile use 22). It says to start the old site from a worktree on a
  copy of the database before upgrading, since `mix brando.upgrade.snapshot`
  needs it running and an old lock can need an older OTP to build again; that
  every `config :brando` change recompiles a `path:` Brando; that the
  post-upgrade `mix format` rewrites `<%= %>` in HEEx to `{}`; that a new test
  database name (`MIX_TEST_PARTITION`) works instead of dropping the old one;
  and not to recreate changed images on the doctor's advice before
  `mix brando.images.adopt --dry-run --verbose` has run with the real media.
  A new checklist gives the grep or SQL for what sites upgraded with an
  earlier Brando revision may still have: `.html` reads on fragments,
  `:entries` relations mapped to `entry_id`, multi-selects without
  `relation:`, `sources:` options on `sequence` or `preload`, module code
  reading `data.vars` or `data.refs`, and picture refs that lost their image.

- **The guides say to keep `:brando` out of `reloadable_apps`.** With it
  listed, Phoenix's code reloader checks Brando's whole source tree on every
  development request, and on Elixir 1.19 and later also rebuilds the
  application's consolidated protocols each time (0.6 to 3 seconds a
  request). `guides/generators.md` said the setting never recompiles a
  dependency; it does, at that cost. The 0.53 upgrade guide now says to
  remove dependencies from `reloadable_apps`, to run `mix deps.compile brando`
  and restart after editing a local checkout, and to develop on Elixir 1.19
  or later, where Phoenix 1.8's code reloader no longer unloads every
  consolidated protocol on each request.
