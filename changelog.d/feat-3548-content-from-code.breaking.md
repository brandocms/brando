- `Brando.Test.insert_block/3`, and `insert_entry/3` with `blocks:`, save the entry through its context, as the admin form does, so the user needs the right to update it.
  Pass `user:` a user who may update the entry (`insert_user/1` gives a superuser).
