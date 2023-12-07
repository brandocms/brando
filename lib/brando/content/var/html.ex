# TODO: DELETE
defmodule Brando.Content.OldVar.Html do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarHtml",
    singular: "var_html",
    plural: "var_htmls",
    gettext_module: Brando.Gettext

  data_layer :embedded
  @primary_key false

  identifier "{{ entry.label }}"

  attributes do
    attribute :type, :string, required: true
    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :value, :text
    attribute :important, :boolean, default: false
    attribute :placeholder, :string
    attribute :instructions, :string
  end

  defimpl Phoenix.HTML.Safe do
    def to_iodata(%{value: value}) do
      value
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end

  defimpl String.Chars do
    def to_string(%{value: value}),
      do:
        value
        |> Phoenix.HTML.raw()
        |> Phoenix.HTML.Safe.to_iodata()
  end
end
