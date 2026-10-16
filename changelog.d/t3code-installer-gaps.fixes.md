- **Users signed in to the admin get past `Brando.Plug.Lockdown`.** The
  plug looked for a `current_user` in the session, which the admin's sign-in
  no longer writes, so only the password or the live preview let anyone in.
  It now checks the admin's session token.
