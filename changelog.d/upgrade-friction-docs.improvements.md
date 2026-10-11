- **The 0.53/0.54 upgrade guide covers what stopped a real 2023 site.**
  `guides/migrating_from_053.md` now opens with a table that picks the guide
  from the newest `brando_NNN` migration, shows the `path:`/`github:` Brando
  dependency and the BrandoJS Yalc steps, lists every dependency constraint a
  2023 `mix.exs` has to change before `mix deps.unlock --all`, and explains
  why Timex and HTTPoison/hackney 1.x packages no longer resolve. It adds the
  Phoenix 1.8 and phoenix_html 4 fallout the tasks leave alone, concrete
  hand-edits for Blueprint migrations on legacy snapshots, a warning that the
  migrations reorder rows behind queries without `ORDER BY`, the `test` alias
  that loads `structure.sql`, and notes on the Dockerfile's frontend Node stage
  and on doctor's admin-assets hint for yarn-era admins.
