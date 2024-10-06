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

  use Spark.Dsl,
    default_extensions: [extensions: [Brando.Blueprint.Meta.Dsl]],
    opts_to_document: []

  def extract_meta(module, data) do
    meta_data =
      module
      |> Spark.Dsl.Extension.get_entities(:meta_schemas)
      |> List.first()

    fields = meta_data.fields

    Enum.reduce(fields, %{}, fn
      %{targets: targets, value_fn: mutator}, acc ->
        targets = (is_list(targets) && targets) || List.wrap(targets)
        result = mutator.(data)

        Enum.reduce(targets, acc, fn target, acc ->
          Map.put(acc, target, result)
        end)
    end)
  end
end
