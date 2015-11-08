use Mix.Config

config :dogma,
  exclude: [
    ~r(\A_build/),
    ~r(\Apriv/),
    ~r(\Atest/),
    ~r(\Atmp/)
  ]
