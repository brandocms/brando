[
  import_deps: [:absinthe, :ecto, :phoenix, :plug, :distillery, :brando],
  inputs: ["*.{ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{ex,exs}"],
  subdirectories: ["priv/*/migrations"]
]
