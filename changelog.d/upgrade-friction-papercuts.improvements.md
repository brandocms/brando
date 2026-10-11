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

- **`mix brando.gen.backend` and `mix brando.gen.frontend` no longer print
  Hex's list of unchanged packages.** Before the binary asset copies they
  queue, Igniter runs `mix deps.get`, whose "Unchanged:" listing of every
  locked package (about 120 lines) buried the generator's own output; it now
  runs quietly, and only its errors print. `mix brando.gen.backend --upgrade` also says
  when the Dockerfile's `assets_frontend` stage builds on another Node image
  than Brando's template (`node:16` where the template has `node:22`), since
  the upgrade only replaces the `assets_backend` stage.
