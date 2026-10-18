- **`mix brando.gen.migrations --refresh` rewrites outdated migration copies.**
  Without the flag the command still only copies missing migrations. With it,
  each existing copy whose code differs from Brando's current template is
  rewritten in place, keeping its file name and timestamp, through the usual
  reviewed plan (`--dry-run` and `--yes` work as before). Formatting and
  comments do not count as a difference. `mix brando.migrations.check` points
  to it when it finds outdated copies.
