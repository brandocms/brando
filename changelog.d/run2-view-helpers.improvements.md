- **`mix brando.migrate54` removes Phoenix.View-era view helpers.** A site
  generated before Phoenix 1.7 stopped at its first compile on
  `use Phoenix.HTML is no longer supported in v4.0`, from
  `<App>Web.ErrorHelpers` or `view_helpers/0` in `<App>Web`. When nothing in
  `lib/` or `test/` uses `use <App>Web, :view`, `<App>Web.view` or
  `ErrorHelpers` outside them (or aliases `<App>Web`, which could hide such
  a use), the task deletes `ErrorHelpers`, `view/0` and
  `view_helpers/0` (and the `use …, :view` example in the moduledoc).
  Otherwise it replaces their `use Phoenix.HTML` with `import Phoenix.HTML`,
  `import Phoenix.HTML.Form` and `use PhoenixHTMLHelpers`, and warns, with
  file and line, that `{:phoenix_html_helpers, "~> 1.0"}` must be added. Any
  other `use Phoenix.HTML` under `lib/` is listed with file and line.
