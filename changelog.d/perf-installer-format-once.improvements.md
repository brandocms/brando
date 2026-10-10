- **`mix brando.install` plans in about 40% less time.** A new file whose
  formatter has no plugins, such as a migration under phx.new's migrations
  formatter, is formatted directly instead of through Igniter's per-file
  round, which evaluated the project's config each time, and the installer no
  longer expands every module alias in the endpoint to find its plugs. The
  planned files are byte for byte the same.
