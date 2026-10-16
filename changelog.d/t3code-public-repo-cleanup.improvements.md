- **`mix brando.install` no longer writes `fabfile.py` or `deployment.cfg`.**
  New applications deploy with Florist (see the deployment guide), and
  `brando.install.fabfile` was already retired. Existing applications keep
  their files, and `mix brando.migrate55` still converts them to
  `florist.config.exs`.
