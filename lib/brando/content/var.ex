defmodule Brando.Content.Var do
  @moduledoc """
  Blueprint for a generic block var.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
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
        :file,
        # todo
        :date,
        :link
      ]

    attribute :label, :string, required: true
    attribute :placeholder, :string
    attribute :key, :string, required: true
    attribute :important, :boolean, default: false
    attribute :instructions, :string
    attribute :value, :text

    # boolean
    attribute :value_boolean, :boolean, default: false

    # color
    attribute :color_picker, :boolean, default: true
    attribute :color_opacity, :boolean, default: false
  end

  relations do
    relation :options, :embeds_many, module: Brando.Content.Var.Option, on_replace: :delete
    relation :palette, :belongs_to, module: Brando.Content.Palette
    relation :image, :belongs_to, module: Brando.Images.Image
    relation :file, :belongs_to, module: Brando.Files.File
    relation :linked_identifier, :belongs_to, module: Brando.Content.Identifier

    # a var can belong to a page, a block, a module, a table template or row, or a global variables set
    relation :page, :belongs_to, module: Brando.Pages.Page
    relation :block, :belongs_to, module: Brando.Content.Block
    relation :module, :belongs_to, module: Brando.Content.Module
    relation :global_set, :belongs_to, module: Brando.Sites.GlobalSet
    relation :table_template, :belongs_to, module: Brando.Content.TableTemplate
    relation :table_row, :belongs_to, module: Brando.Content.TableRow
  end

  defimpl String.Chars do
    def to_string(%{type: :string, value: value}) do
      value
    end

    def to_string(%{type: _} = var) do
      inspect(var, pretty: true)
    end
  end
end
