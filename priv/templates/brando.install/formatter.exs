[
  import_deps: [:absinthe, :ecto, :phoenix, :plug, :brando],
  inputs: ["*.{ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{ex,exs}"],
  surface_inputs: ["{lib,test}/**/*.{ex,exs,sface}"],
  subdirectories: ["priv/*/migrations"]
]
