- **`mix brando.install` keeps the version in `VERSION` and imports Brando's
  formatting.** phx.new's inline `version: "0.1.0"`, or a literal `@version`,
  moves to a `VERSION` file that `mix.exs` reads, which is where Florist looks
  for the release version. An existing `VERSION` is kept, and `mix.exs` reads
  it when the two agree. `.formatter.exs` gets `:brando` in `import_deps`, so
  `mix format` keeps Blueprint DSL calls without parentheses.

- **`mix brando.gen.site` adds the site's error pages and the lockdown page.**
  404 and 500 render in the site's layout, replacing phx.new's `ErrorHTML`
  (and its plain-text test) while it is unchanged. `Brando.Plug.Lockdown` goes
  in the `:brando_site` pipeline, with `YourWeb.CMS.LockdownController` at
  `/coming-soon` for it to send visitors to, so `lockdown: true` no longer
  crashes on the missing `lockdown_path`. A site generated earlier gets the
  lockdown page when the task runs again. See "Error pages" and "Lockdown" in
  the generators guide.
