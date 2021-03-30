defmodule Brando.Sites.Global do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Sites",
    schema: "Global",
    singular: "global",
    plural: "globals"

  alias Brando.Sites.GlobalCategory

  identifier "{{ entry.label }}"

  attributes do
    attribute :type, :string, required: true
    attribute :label, :string, required: true
    attribute :key, :string, required: true
    attribute :data, :map, required: true
  end

  relations do
    relation :global_category, :belongs_to, module: GlobalCategory
  end

  defimpl Phoenix.HTML.Safe, for: __MODULE__ do
    def to_iodata(%{type: "text", data: data}) do
      data
      |> Map.get("value", "")
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{type: "boolean", data: data}) do
      data
      |> Map.get("value", false)
      |> to_string()
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{type: "html", data: data}) do
      data
      |> Map.get("value", "")
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{type: "color", data: data}) do
      data
      |> Map.get("value", "")
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end
end
