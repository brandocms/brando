- Migrations that `mix brando.gen.migrations` copies pass a new site's `mix format --check-formatted`; until now `brando_244`'s copy could fail it, and so `mix precommit`.
  In a project whose copy fails it, run `mix format`. `mix brando.migrations.check` and `--refresh` do not count formatting, so nothing else changes.
