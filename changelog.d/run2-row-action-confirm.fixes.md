- **A listing row action's `confirm:` is translated.** The confirmation of a
  custom `action` showed its msgid, while its label and a selection action's
  confirmation were translated in the schema's Gettext domain. Write it with
  `t("…")` like the label; `mix brando.migrate54` now rewrites
  `confirm: gettext("…")` on actions as well.
