- **Generated pages and error pages end clear of the footer, and the footer
  reaches the bottom of a short page** (#3238). The installed frontend gives the
  last `main > .page-section` the same `@space padding-bottom xl;` the first
  gets at the top, so a generated entry page's back link and an index's list
  no longer sit against the footer. `body` is a column at least the window
  tall and `main` takes the slack, which replaces `html, body { min-height:
  100%; }`, a rule that had no effect. The 404 and 500 pages wrap their
  content in `.page-section` and `.inner` like the generated pages, so they
  get the container and indent instead of starting at the window's edge, and
  a section's `h1` followed by text gets `@space margin-bottom md;`. In an
  existing site, add `main > .page-section:last-child { @space
  padding-bottom xl; }`, `flex-grow: 1;` on `main`, and `@display
  flex/column/nowrap; min-height: 100dvh;` on `body`.

- **`mix brando.install` ignores all of `priv/static`** (#3238). The listed
  paths missed what `mix brando.digest` adds next to them
  (`manifest-<hash>.json`, `.gz` copies, `favicon-<hash>.ico`), which showed up
  as untracked files after a local production build. `priv/static` only holds
  build output in a Brando application, so the installer now writes
  `/priv/static/` instead. Without the CMS public site, phx.new's
  `priv/static/robots.txt` moves to `assets/frontend/public/robots.txt`, so it
  stays tracked and reaches the release, which never had it: the Docker build
  leaves `priv/static` out. A `.gitignore` with an exception inside
  `priv/static` (`!/priv/static/.well-known/`) gets a notice instead of the
  line, which would cancel it.
