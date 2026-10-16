- **`mix brando.install` keeps the version in `VERSION` and imports Brando's
  formatting.** phx.new's inline `version: "0.1.0"`, or a literal `@version`,
  moves to a `VERSION` file that `mix.exs` reads, which is where Florist looks
  for the release version. An existing `VERSION` is kept, and `mix.exs` reads
  it when the two agree. A Dockerfile that copies `mix.exs` (like
  `mix phx.gen.release --docker`'s) gets `COPY VERSION` after it, so the image
  build can still evaluate `mix.exs`. `.formatter.exs` gets `:brando` in
  `import_deps`, so `mix format` keeps Blueprint DSL calls without
  parentheses; the Hex package now ships the `.formatter.exs` that reads.

- **`mix brando.gen.site` adds the site's error pages and the lockdown page.**
  404 and 500 render in the site's layout, replacing phx.new's `ErrorHTML`
  (and its plain-text test, from phx.new 1.7 or 1.8) while it is unchanged.
  `Brando.Plug.Lockdown` goes in the `:brando_site` pipeline, with
  `YourWeb.CMS.LockdownController` at `/coming-soon` for it to send visitors
  to, so `lockdown: true` no longer crashes on the missing `lockdown_path`.
  Rerunning the task on a site generated earlier adds the lockdown page while
  the files and routes it owns are unchanged; a customized one is reported
  instead. See "Error pages" and "Lockdown" in the generators guide.
