defmodule Brando.Content.Var.Select do
  defmodule Option do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Content",
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

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "VarSelect",
    singular: "var_select",
    plural: "var_selects",
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
    attribute :default, :string
    attribute :instructions, :string
  end

  relations do
    relation :options, :embeds_many, module: __MODULE__.Option, on_replace: :delete
  end

  defimpl String.Chars, for: __MODULE__ do
    def to_string(%{value: value}), do: value
  end
end
