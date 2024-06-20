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
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped

  identifier false
  persist_identifier false

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
    attribute :config_target, :text

    # boolean
    attribute :value_boolean, :boolean, default: false

    # color
    attribute :color_picker, :boolean, default: true
    attribute :color_opacity, :boolean, default: false

    # link
    attribute :link_text, :string
    attribute :link_type, :enum, values: [:url, :identifier], default: :url
    attribute :link_identifier_schemas, {:array, :string}, default: []
    attribute :link_target_blank, :boolean, default: false
    attribute :link_allow_custom_text, :boolean, default: true

    # layout
    attribute :width, :enum,
      values: [
        :full,
        :half,
        :third
      ],
      default: :full
  end

  relations do
    relation :options, :embeds_many, module: Brando.Content.Var.Option, on_replace: :delete
    relation :palette, :belongs_to, module: Brando.Content.Palette
    relation :image, :belongs_to, module: Brando.Images.Image
    relation :file, :belongs_to, module: Brando.Files.File
    relation :identifier, :belongs_to, module: Brando.Content.Identifier

    # a var can belong to a page, a block, a module, a table template or row,
    # a global variables set or a menu item link
    relation :page, :belongs_to, module: Brando.Pages.Page
    relation :block, :belongs_to, module: Brando.Content.Block
    relation :module, :belongs_to, module: Brando.Content.Module
    relation :table_template, :belongs_to, module: Brando.Content.TableTemplate
    relation :table_row, :belongs_to, module: Brando.Content.TableRow
    relation :global_set, :belongs_to, module: Brando.Sites.GlobalSet
    relation :menu_item, :belongs_to, module: Brando.Navigation.Item
  end

  defimpl String.Chars do
    def to_string(%{type: :string, value: value}) do
      value
    end

    def to_string(%{type: _} = var) do
      inspect(var, pretty: true)
    end
  end

  defimpl Phoenix.HTML.Safe do
    def to_iodata(%{type: :link, link_type: :url, value: value}) do
      value
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{type: :link, link_type: :identifier, identifier: identifier}) do
      identifier.url
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end
end
