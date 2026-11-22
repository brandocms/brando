- `Brando.Test.insert_block/3`, and `insert_entry/3` with `blocks:`, save the entry through its context, as the admin form does, so the user needs the right to update it.
  Pass `user:` a user who may update the entry (`insert_user/1` gives a superuser).
- `Brando.Test.render_block/2` and `build_block/2` set an HTML or SVG ref's markup (a map with `text`, `params`, `code` or `class`) only for a superuser, and refuse media a ref does not take (a video for a picture ref), as the editor does.
  Pass `user: insert_user()` to tests that set such markup, and give each ref the media its module allows.
