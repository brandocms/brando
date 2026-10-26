- Refused form posts (failed validation or Turnstile) no longer count against the form's submission budget, and a visitor over its own limit stops before touching it, so one client's refused posts cannot block a form for everyone.

- Form submissions, static and `LiveForm`, count visitors by their own address behind a trusted reverse proxy (`Brando.ClientIP`), not the proxy's, and an IPv6 visitor by its /64.

- The GitHub Markdown webhook counts only deliveries whose signature verified against its node-wide budget, counts clients by their own address behind a trusted proxy, and answers 429 when rate-limited.

- `/health` answers only requests from the server itself, no longer visitors forwarded by a reverse proxy on it.

- The lockdown password allows 10 wrong attempts per client address (an IPv6 one by its /64) in 15 minutes, through `?key=` and `Brando.Plug.Lockdown.password?/2`; `password?/1` is deprecated.
