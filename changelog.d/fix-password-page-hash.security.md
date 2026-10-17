- **Password forms no longer put the account's password hash in the page**.
  The bcrypt hash of a user's password was the `value` of the new-password
  input on `/admin/users/password` (every visit, not only the first login), on
  the page a reset link opens, and, for the edited user, in the user form's
  "Set a password" dialog. Anyone who could read the page source, including a
  superuser for other users, could take the hash for offline guessing, and
  the field had to be cleared before a new password could be typed into it.
  A password input in the admin now shows only what was typed into it
  (`BrandoAdmin.Components.Form.Primitives.password_value/1`).
