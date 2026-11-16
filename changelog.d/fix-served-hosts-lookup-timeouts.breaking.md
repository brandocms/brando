- The served hosts check asks the name servers in `/etc/resolv.conf` itself, through `:inet_res`, and no longer reads `/etc/hosts` or platform-specific resolver configuration.
  An installation whose hosts resolve only through those sets
  `resolver: Brando.Tenant.ServedHosts.SystemResolver` in `config :brando, Brando.Tenant.ServedHosts`.
  A custom `:resolver` may answer `{:incomplete, addresses, families}` for a lookup that could not read a family; its other answers mean what they did.
