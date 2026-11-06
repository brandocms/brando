- `mix brando.install` writes a `CLAUDE.md` that imports `AGENTS.md`, a site section in `AGENTS.md` (the client, how to run the site, when to load the frontend skills), and two new skills: `brando-frontend` (the public site's CSS, module styling, palettes, Moonwalk, fonts) and `brando-europacss` (the native EuropaCSS compiler). A versioned `mix brando.upgrade` adds them where they are missing.
  Fill in the `TODO` in the site section of `AGENTS.md`. A hand-written `CLAUDE.md` is kept: move what it adds into `AGENTS.md` and replace it with a line reading `@AGENTS.md`.

- `mix brando.gen.agents` adds the agent files on their own, and `--refresh` replaces the skill files with the versions Brando ships.
