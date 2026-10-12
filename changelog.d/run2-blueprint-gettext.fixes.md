- **`mix brando.migrate54` writes Blueprint labels with `t/1`, and
  `mix brando.migrate55` brings their translations along.** The admin
  translates a Blueprint's tab names, alerts, input and fieldset labels,
  placeholders and instructions, listing filter, action, sort and export
  labels, selection action confirmations and `translate` values in the
  schema's own Gettext domain, `<domain>_<schema>`. A label written as
  `gettext("Content")` was extracted into `default` instead, so it showed in
  English. `migrate54` now rewrites a literal `gettext/1` in those places to
  `t/1` and lists, with file and line, the Gettext calls there it cannot
  rewrite (`gettext/2` with bindings, `ngettext`, an interpolated msgid).
  `migrate55` copies the `default` domain's translation of each `t/1` label
  into `<domain>_<schema>.po` in the backend's locale directories, never
  replacing a translation already there, so "Content" stays "Innhold"
  without `scripts/sync_gettext.sh`.
