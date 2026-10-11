- **`mix brando.doctor` gives the whole fix for old admin assets.** For an
  `assets/backend` that is not a pnpm project yet (a yarn or npm lockfile, no
  `packageManager: pnpm@…`), the admin assets finding now says to run
  `mix brando.gen.backend --upgrade` and then
  `mix brando.assets.setup --backend-only`; for an older `.yalc` copy it
  includes `npx yalc publish` in Brando's assets before the `yalc update`.
  Images made before Brando recorded their settings that all differ from
  their config now say so ("all 378 differ from their config") in the words
  `mix brando.images.adopt` uses, and the fix names
  `mix brando.images.adopt --dry-run --verbose` for the reasons. The Oban
  check's job queries are no longer logged, so a doctor run in development
  stops printing a raw `SELECT … FROM oban_jobs`.
