- **A released Brando installs BrandoJS from npm**. The generated admin pins
  `@brandocms/brandojs` to Brando's own version, and `mix brando.assets.setup`
  runs `pnpm install` without needing a BrandoJS checkout or Yalc. A
  development version (`-dev`), which has no npm release, still takes BrandoJS
  from the Brando checkout through Yalc, and so does working on Brando itself:
  `mix brando.assets.setup --local` (or `--source PATH`) switches the admin to
  a Yalc copy, whose `npx yalc publish` reaches the running Vite dev server,
  and `--npm` switches back and removes the copy. Without an option the task
  keeps the source `package.json` names.

- **Upgrades keep where the admin takes BrandoJS from**. `mix brando.gen.backend
  --upgrade` moves an npm pin to Brando's version and leaves a Yalc copy or
  linked checkout alone, with a notice suggesting `--npm` once Brando is a
  release. The template Dockerfile copies `assets/backend/.yalc` only when it
  exists, so one Dockerfile builds either. `yalcAutoUpdate` follows Yalc
  publishes only while `package.json` takes BrandoJS from `.yalc`, so a
  `yalc.lock` left behind no longer swaps the npm copy for the store's, and
  `mix brando.doctor` reads an npm install from `node_modules`.
