[
  import_deps: [:ecto, :phoenix, :plug, :brando, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{ex,exs,heex}",
    "priv/*/seeds.exs",
    "priv/repo/ensure_e2e_seeds.exs",
    "priv/repo/prepare_e2e.exs",
    "{config,lib,test}/**/*.{ex,exs,heex}"
  ],
  subdirectories: ["priv/*/migrations"]
]
