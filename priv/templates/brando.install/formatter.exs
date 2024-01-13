[
  import_deps: [:ecto, :phoenix, :plug, :brando],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{ex,exs,heex}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{ex,exs,heex}"],
  subdirectories: ["priv/*/migrations"]
]
