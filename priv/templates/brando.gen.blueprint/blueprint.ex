defmodule <%= app_module %>.<%= domain %>.<%= schema %> do
  @moduledoc """
  Blueprint for <%= schema %>
  """

  use Brando.Blueprint,
    application: "<%= app_module %>",
    domain: "<%= domain %>",
    schema: "<%= schema %>",
    singular: "<%= Macro.underscore(schema) %>",
    plural: "<%= Macro.underscore(schema) %>s"

  use Gettext, backend: <%= app_module %>Admin.Gettext

  # trait :blocks
  # trait :creator
  # trait :meta
  # trait :revisioned
  # trait :scheduled_publishing
  # trait :sequenced
  # trait :soft_delete, obfuscated_fields: [:slug]
  # trait :status
  # trait :timestamped
  # trait :translatable

  identifier "{{ entry.title }}"
  # NOTE: If using Brando.Trait.Translatable, change `route` to `route_i18n(@entry, ...)`
  absolute_url ~H|{route(:<%= Macro.underscore(schema) %>_path, :detail, [@entry.slug])}|

  attributes do
  end

  relations do
  end

  translations do
    context :naming do
      translate :singular, t("<%= Macro.underscore(schema) |> Brando.Utils.humanize(:downcase) %>")
      translate :plural, t("<%= Macro.underscore(schema) |> Brando.Utils.humanize(:downcase) %>s")
    end
  end
end
