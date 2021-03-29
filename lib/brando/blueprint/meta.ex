defmodule Brando.Blueprint.Meta do
  @moduledoc """
  Define a meta schema

  ## Example

  In your blueprint:

      use Brando.Blueprint

      meta_schema do
        meta_field ["description", "og:description"], &Brando.HTML.truncate(&1, 155)
        meta_field ["title", "og:title"], [:title]
        meta_field ["title", "og:title"], &fallback(&1, [:meta_title, :title])
        meta_field "og:image", [:meta_image]
        meta_field "og:locale", [:language], &encode_locale/1
      end

  `fallback(data, keys)` tries `keys` until it gets a value, so in the above example it
  first tries to get `data.meta_title`, if that fails it tries `data.title`.

  `encode_locale(language)` converts the locale to a format facebook/opengraph understands.
  """

  defmacro meta_schema(do: block), do: do_meta_schema(block)

  defp do_meta_schema(block) do
    prelude =
      quote do
        try do
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote unquote: false do
        fields = @meta_fields |> Enum.reverse()

        def __meta_schema__(:fields), do: unquote(fields)

        def extract_meta(data) do
          Brando.Blueprint.Meta.extract_meta(__MODULE__, data)
        end
      end

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  @doc """
  Defines a META field.

  This macro defines

    * a field name
    * a path to extract the data from
    * a mutator/generator function


  ### Examples

      meta_field "title", fn data -> generate_crazy_title(data.title) end

  If no `path` is supplied, the entire data map is passed to the supplied mutator function

      meta_field ["description", "og:description"], [:meta_description], &truncate(&1, 155)

  This defines two fields, `description` and `og:description`. It should get its value from
  `meta_description` from the provided data map. This data gets passed to `truncate/1`.

  If the data passed to a `meta_field` mutator function is the raw data (there is no extraction path provided),
  you can access the `current_url` in `data.__meta__.current_url`

      meta_field "og:url", &(&1.__meta__.current_url)

  To grab an image from `identity`

      meta_field ["image", "og:image"], &get_org_image(&1)

  """
  defmacro meta_field(name, _) when is_atom(name),
    do: raise("Brando META: field name must be a binary or a list of binaries, not an atom.")

  defmacro meta_field(name, _, _) when is_atom(name),
    do: raise("Brando META: field name must be a binary or a list of binaries, not an atom.")

  defmacro meta_field(list_of_names, path) when is_list(list_of_names) and is_list(path) do
    for name <- list_of_names do
      quote do
        meta_field(unquote(name), unquote(path))
      end
    end
  end

  defmacro meta_field(list_of_names, path, function)
           when is_list(list_of_names) and is_list(path) do
    for name <- list_of_names do
      quote do
        meta_field(unquote(name), unquote(path), unquote(function))
      end
    end
  end

  defmacro meta_field(list_of_names, function) when is_list(list_of_names) do
    for name <- list_of_names do
      quote do
        meta_field(unquote(name), unquote(function))
      end
    end
  end

  defmacro meta_field(name, path) when is_binary(name) and is_list(path) do
    quote do
      Module.put_attribute(__MODULE__, :meta_fields, unquote(name))

      def __meta_field__(unquote(name), data) do
        get_in(data, Enum.map(unquote(path), &Access.key/1))
      end
    end
  end

  defmacro meta_field(name, path, mutator_function) when is_binary(name) and is_list(path) do
    quote do
      Module.put_attribute(__MODULE__, :meta_fields, unquote(name))

      def __meta_field__(unquote(name), data) do
        value = get_in(data, Enum.map(unquote(path), &Access.key/1))
        unquote(mutator_function).(value)
      end
    end
  end

  defmacro meta_field(name, mutator_function) when is_binary(name) do
    quote do
      Module.put_attribute(__MODULE__, :meta_fields, unquote(name))

      def __meta_field__(unquote(name), data) do
        unquote(mutator_function).(data)
      end
    end
  end

  @doc """
  Extract META information from `data` against `mod`'s `meta_schema`
  """
  def extract_meta(mod, data) do
    Enum.reduce(
      mod.__meta_schema__(:fields),
      %{},
      fn name, acc ->
        Map.put(acc, name, mod.__meta_field__(name, data))
      end
    )
  end

  def fallback(data, keys) when is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _ ->
      case Map.get(data, key) do
        nil -> {:cont, nil}
        val -> {:halt, val}
      end
    end)
  end

  @spec encode_locale(binary) :: binary
  def encode_locale("en"), do: "en_US"
  def encode_locale("no"), do: "nb_NO"
  def encode_locale("nb"), do: "nb_NO"
  def encode_locale("nn"), do: "nn_NO"
  def encode_locale(locale), do: locale
end
