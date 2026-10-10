- **`mix brando.install` plans in about half the time.** A new file whose
  formatter has no plugins is formatted directly instead of through Igniter's
  per-file round, which evaluated the project's config each time, and the
  installer no longer expands every module alias in the endpoint to find its
  plugs. The planned files are byte for byte the same.
