locals_without_parens = [
  sequence: 2,
  villain: 1,
  datasource: 2,
  datasources: 1,
  query: 3,
  default: 1,
  filters: 1,
  has_image_field: 2,
  can: 2,
  can: 3,
  cannot: 2,
  cannot: 3,
  rules: 2,
  assign: 2,
  many: 2,
  one: 2
]

[
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens],
  import_deps: [:absinthe, :ecto, :ecto_sql, :phoenix, :plug, :phoenix_html],
  inputs: ["*.{ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{ex,exs}"],
  subdirectories: ["priv/*/migrations"]
]
