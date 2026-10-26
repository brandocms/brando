- The live preview page no longer carries the viewing user's admin socket token: its socket connects with a 15-minute token that joins only that preview's channel. Script in previewed content still runs on the admin origin as the viewer; the Live preview guide says what it can reach and how a `script-src` limits it.

- Live preview responses send a Content-Security-Policy (`frame-ancestors 'self'; base-uri 'self'`); add directives such as a `script-src` with `config :brando, :live_preview_content_security_policy, "…"` (see the Live preview guide).

- The live preview escapes its preview key into the page instead of writing it raw into a script.
