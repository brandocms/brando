- A multi-site installation can keep a file of the hosts it serves for the reverse proxy to route and certify, adding each bound host once its DNS points at the server, and the Environments screen shows where each host stands.
  To use it, set `config :brando, Brando.Tenant.ServedHosts, file: "/path/to/served_hosts"` in `config/runtime.exs` and build the proxy's routes from that file.
