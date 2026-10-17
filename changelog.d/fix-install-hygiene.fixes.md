- **A new application's built files stay out of Git.** The `.gitignore` lines
  `mix brando.install` adds now cover `priv/static/favicon.ico` and
  `priv/static/images/`, which the Vite builds copy from the asset projects'
  `public/` folders.
- **Missing identity or SEO settings are a warning, not an error.**
  `Brando.System` logged `No identities found.` and `No seo entries found.` as
  errors during every `mix brando.setup` (before seeding) and every test run
  of a new application. They are warnings now, naming `mix brando.gen.seeds`,
  and the test environment, whose database starts empty, skips the check.
- **`mix brando.assets.setup` adds BrandoJS's Yalc copy without the pnpm
  warning.** `yalc add` also wrote the package into `node_modules`, which
  `pnpm install` then moved to `node_modules/.ignored` with a warning. It now
  runs with `--pure` and the task writes the `file:.yalc/@brandocms/brandojs`
  dependency itself.
