- `mix brando.entries.resave` and `mix brando.identifiers.sync` end by saying to restart running
  servers or empty their caches ([#3172](https://github.com/brandocms/brando/pull/3172)).

- `mix brando.upgrade.snapshot urls` picks each Blueprint's heaviest entry per language and, with
  `--base-url`, skips the old site's 404s ([#3172](https://github.com/brandocms/brando/pull/3172)).

- `mix brando.doctor` and `scripts/prepare_055_deps.exs` warn about a Node.js on the PATH that is an
  odd release, older than Brando is tested on, or a 22 before 22.12
  ([#3172](https://github.com/brandocms/brando/pull/3172)).
