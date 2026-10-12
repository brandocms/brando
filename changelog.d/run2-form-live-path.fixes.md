- **`mix brando.migrate54` writes each FormLive beside the list LiveView.**
  It replaced a generated Create/Update pair under
  `lib/<app>_admin/live/<domain>/` with a FormLive, and its notice named that
  directory, but Igniter moved the new file to the path its module name maps
  to, `lib/<app>_admin/<domain>/`. The FormLive is now written where the
  `UpdateLive` it replaces was, the path the notice prints, so there is
  nothing to `git mv`.
