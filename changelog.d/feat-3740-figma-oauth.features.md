- Figma connects with OAuth through each site environment's own Figma app, saved under Configuration → Integrations → Connected AI tools: the connected tools' access renews itself, a pasted token stays the fallback for an environment without a connected app, and `brando_figma_status` says which one calls use.
  Run `mix brando.gen.migrations` for `brando_242`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
  To connect, register an app in Figma per environment with the redirect URL the settings page shows and the scopes `file_content:read` and `current_user:read`.
