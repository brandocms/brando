defmodule <%= app_module %>.<%= domain %>.<%= schema %> do
  use Brando.Blueprint,
    application: "<%= app_module %>",
    domain: "<%= domain %>",
    schema: "<%= schema %>",
    singular: "<%= Recase.to_snake(schema) %>",
    plural: "<%= Recase.to_snake(schema) %>s"

  import Brando.Gettext

  # trait Brando.Trait.Creator
  # trait Brando.Trait.Meta
  # trait Brando.Trait.Revisioned
  # trait Brando.Trait.ScheduledPublishing
  # trait Brando.Trait.Sequenced
  # trait Brando.Trait.SoftDelete, obfuscated_fields: [:slug]
  # trait Brando.Trait.Status
  # trait Brando.Trait.Timestamped
  # trait Brando.Trait.Translatable
  # trait Brando.Trait.Villain

  identifier "{{ entry.title }}"
  absolute_url "{% route <%= Recase.to_snake(schema) %>_path detail { entry.slug } %}"

  attributes do
  end

  relations do
  end
end
