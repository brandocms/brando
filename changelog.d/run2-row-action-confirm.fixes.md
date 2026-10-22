- A listing row action's `confirm:` is translated in the schema's Gettext domain
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
  Write it with `t("…")`; `mix brando.migrate54` rewrites `confirm: gettext("…")`.
