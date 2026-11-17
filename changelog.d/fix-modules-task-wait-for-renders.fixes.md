- `mix brando.modules import`, `refresh` and `resolve --apply` wait until the entries they queued have rendered, exit non-zero naming any that failed or are left at `--timeout`, and stop the application before returning, so no render is left stuck in `executing`; `--no-wait` leaves the renders to the running server, and the commands no longer start the definition watcher.

- A server that stops lets the Oban jobs it is running finish within Oban's `shutdown_grace_period`, instead of stopping them after five seconds and leaving them `executing` until Oban's Lifeline rescues them.
