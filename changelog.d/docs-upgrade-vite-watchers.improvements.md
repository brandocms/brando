- The 0.53/0.54 upgrade guide says to add the `Brando.Vite` watchers to
  `config/dev.exs`: no source task adds them, so an upgraded site's
  `mix phx.server` otherwise serves pages whose assets never load.
