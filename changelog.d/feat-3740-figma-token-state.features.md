- Connected AI tools say why Figma refused a call (an expired token, an invalid token, a token without the permission to read files, or a file its owner cannot open, in Figma's words), the MCP settings page checks the Figma token with Figma and records its expiry date to warn a week ahead, and a new read-only tool, `brando_figma_status`, lets a tool check the token before it starts.
  Run `mix brando.gen.migrations` for `brando_240`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
  For the check to work, a pasted Figma token needs the `current_user:read` scope beside `file_content:read`.
