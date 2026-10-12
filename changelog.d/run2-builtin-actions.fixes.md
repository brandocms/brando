- **`mix brando.migrate54` removes listing actions that repeat the
  built-ins.** 0.53 generators declared edit, duplicate and delete as
  listing actions (`event: "edit_entry"`, …). A listing's `default_actions`
  offers the same three, so each row menu showed them twice. The task now
  removes an `action` with one of those events, in the 0.53 `actions [...]`
  list or an `action` an earlier run wrote, and names each in its notice. A
  listing with `default_actions false` keeps them, and one with options
  beyond `label`, `event` and `confirm` is kept and listed with file and
  line.
