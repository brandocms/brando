defmodule Brando.Blocks.Var do
  defmodule Option do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Blocks",
      schema: "VarSelectOption",
      singular: "var_select_option",
      plural: "var_select_options",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded

    identifier "{{ entry.label }}"

    attributes do
      attribute :label, :text, required: true
      attribute :value, :text, required: true
    end
  end

  @moduledoc """
  Blueprint for a generic block var.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Blocks",
    schema: "Var",
    singular: "var",
    plural: "vars",
    gettext_module: Brando.Gettext

  # ++ Traits
  trait Brando.Trait.Creator
  trait Brando.Trait.Revisioned
  trait Brando.Trait.Sequenced, append: true
  trait Brando.Trait.Timestamped

  attributes do
    attribute :type, :enum,
      required: true,
      values: [
        :boolean,
        :string,
        :text,
        :html,
        :image,
        :datetime,
        :color,
        :select,
        # todo
        :file,
        :link
      ]

    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :value_string, :text
    attribute :value_datetime, :datetime
    attribute :important, :boolean, default: false
    attribute :default, :string
    attribute :instructions, :string

    # color
    attribute :color_picker, :boolean, default: true
    attribute :color_opacity, :boolean, default: false
  end

  relations do
    relation :options, :embeds_many, module: __MODULE__.Option, on_replace: :delete
    relation :palette, :belongs_to, module: Brando.Content.Palette
    relation :image, :belongs_to, module: Brando.Images.Image
    relation :file, :belongs_to, module: Brando.Files.File
    relation :linked_identifier, :belongs_to, module: Brando.Content.Identifier
  end
end
