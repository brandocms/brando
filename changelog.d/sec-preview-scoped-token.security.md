- The live preview page no longer carries the viewing user's admin socket token: its socket connects with a 15-minute token that joins only that preview's channel, so script in previewed content cannot use it for other admin channels.

- Live preview responses send a Content-Security-Policy (`frame-ancestors 'self'; base-uri 'self'`); add directives such as a `script-src` with `config :brando, :live_preview_content_security_policy, "…"` (see the Live preview guide).

- The live preview escapes its preview key into the page instead of writing it raw into a script.
