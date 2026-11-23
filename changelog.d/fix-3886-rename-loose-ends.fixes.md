- Renames refused for moving values in too many blocks print the whole `mix brando.modules resolve` command to run after the apply, with `--uid`, `--user` and `--apply`, one per module.

- On Release changes, a conflict that takes the release's version says when the apply moves values to renamed refs and vars, and that it then can't be reverted.

- An editor's save that Postgres cancels because it waited on the same blocks as another write (a release apply moving values) keeps the form open with what was typed and asks to save again, instead of crashing the form.
