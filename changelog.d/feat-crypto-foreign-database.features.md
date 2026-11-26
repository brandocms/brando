- A database copied from another host has its active webhooks and notification routes paused at start, and the dashboard says where it came from and which were paused; one written with another encryption secret is reported by `mix brando.doctor`, the System check and the dashboard, with what it cannot read and whether the secret changed here or the database came from elsewhere.
  Run `mix brando.gen.migrations` for `brando_252`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.

- What the encryption secret cannot read can be forgotten under Configuration → Encrypted data or with `bin/my_app eval "Brando.Release.forget_unreadable()"` (unreadable two-factor secrets reset, passkeys kept; unreadable webhooks and routes paused; unreadable Figma credentials removed), and `bin/my_app eval 'Brando.Release.reset_two_factor("…")'` turns one user's two-factor authentication off from the server.
