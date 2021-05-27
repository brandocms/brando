locals_without_parens = [
  absolute_url: 1,
  identifier: 1,
  meta: 2,
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
  merge: 1,
  many: 2,
  list: 2,
  selection: 3,
  single: 2,
  mutation: 2,
  mutation: 3,
  # live preview
  preview_target: 2,
  assign: 2,
  schema_module: 1,
  schema_preloads: 1,
  mutate_data: 1,
  layout_module: 1,
  layout_template: 1,
  view_module: 1,
  view_template: 1,
  template_section: 1,
  template_prop: 1,
  # blueprints
  application: 1,
  domain: 1,
  schema: 1,
  singular: 1,
  plural: 1,
  trait: 1,
  trait: 2,
  t: 2,
  attribute: 2,
  attribute: 3,
  relation: 2,
  relation: 3,
  extra_field: 3,
  label: 1,
  placeholder: 1,
  instructions: 1,
  translate: 2,
  meta_schema: 1,
  meta_field: 2,
  meta_field: 3,
  json_ld_schema: 2,
  json_ld_field: 2,
  json_ld_field: 3,
  json_ld_field: 4,
  table: 1,
  primary_key: 1,
  data_layer: 1,
  input: 2,
  input: 3,
  fieldset: 1,
  fieldset: 2,
  listing_field: 1,
  listing_field: 2,
  listing_field: 3,
  listing_template: 1,
  listing_template: 2,
  listing_query: 1,
  listing_actions: 1,
  listing_selection_actions: 1
]

[
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens],
  import_deps: [:absinthe, :ecto, :ecto_sql, :phoenix, :plug, :phoenix_html, :surface],
  inputs: ["*.{ex,exs}", "priv/*/seeds.exs", "{config,lib,test}/**/*.{ex,exs}"],
  subdirectories: ["priv/*/migrations"]
]
