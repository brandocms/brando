defmodule Brando.Blueprint.Meta do
  @moduledoc """
  Define a meta schema

  ## Example

  In your blueprint:

      use Brando.Blueprint,
        # ...

      meta_schema do
        field ["description", "og:description"], &Brando.HTML.truncate(&1, 155)
        field ["title", "og:title"], & &1.title
        field ["title", "og:title"], &fallback([&1.meta_title, {:strip_tags, &1.title}])
        field "og:image", & &1.meta_image
        field "og:locale", &encode_locale(&1.language)
      end

  `fallback(values)` tries `values` until it gets a value, so in the above example it
  first tries to get `data.meta_title`, if that fails it tries `data.title`, but will strip
  it for HTML tags.

  `encode_locale(language)` converts the locale to a format facebook/opengraph understands.
  """

  @doc """
  Extracts configured metadata pairs from a Blueprint entry.

  A field is omitted when its value function returns `nil` or reads a missing key.
  Other exceptions propagate so invalid metadata functions remain visible during
  development instead of being silently discarded.
  """
  @spec extract_meta(module(), term()) :: [{String.t(), term()}]
  def extract_meta(module, data) do
    module
    |> Spark.Dsl.Extension.get_entities(:meta_schemas)
    |> List.first()
    |> extract_fields(data)
  end

  defp extract_fields(nil, _data), do: []

  defp extract_fields(meta_schema, data) do
    Enum.flat_map(meta_schema.fields, &extract_field(&1, data))
  end

  defp extract_field(%{targets: targets, value_fn: value_fn}, data) do
    case safe_apply(value_fn, data) do
      nil -> []
      value -> Enum.map(List.wrap(targets), &{&1, value})
    end
  end

  defp safe_apply(fun, data) do
    fun.(data)
  rescue
    KeyError -> nil
  end
end
