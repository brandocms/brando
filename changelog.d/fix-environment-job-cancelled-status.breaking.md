- A scheduled environment copy or live switch cancelled when it was due, because whoever scheduled it may no longer carry it out, shows in the Environments screen's operation log as Cancelled, with who scheduled it and why.
  Run `mix brando.gen.migrations` and `mix brando.migrate` for brando_223, which adds `cancelled_reason` to `environment_operation_logs`.
