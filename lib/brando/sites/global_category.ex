defmodule Brando.Sites.GlobalCategory do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "GlobalCategory",
    singular: "global_category",
    plural: "global_categories",
    gettext_module: Brando.Gettext

  alias Brando.Content.Var

  trait Brando.Trait.CastPolymorphicEmbeds

  identifier "{{ entry.label }}"

  attributes do
    attribute :label, :string, required: true
    attribute :key, :string, unique: [prevent_collision: true], required: true

    attribute :globals, {:array, PolymorphicEmbed},
      types: [
        boolean: Var.Boolean,
        text: Var.Text,
        string: Var.String,
        datetime: Var.Datetime,
        html: Var.Html,
        color: Var.Color
      ],
      type_field: :type,
      on_type_not_found: :raise,
      on_replace: :delete
  end
end
