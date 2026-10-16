- **Users with admin access get past `Brando.Plug.Lockdown`.** The plug
  looked for a `current_user` in the session, which the admin's sign-in no
  longer writes, so only the password or the live preview let anyone in. It
  now checks the admin's session token and the account's backend access:
  group grants with groups authorization, the legacy role without.
- **`Brando.Plug.Lockdown` no longer unlocks on an empty password.** With
  `lockdown_password: ""`, `?key=` authorized any visitor; an empty password
  now counts as none. The key is compared in constant time.
- **Shared preview links work while a site is locked.** `/__p__/…` links,
  for reviewers without an admin account, are no longer redirected to
  `/coming-soon`.
