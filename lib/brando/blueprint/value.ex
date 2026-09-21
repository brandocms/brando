defmodule Brando.Blueprint.Value do
  @moduledoc """
  Resolves fallback values used by Blueprint metadata and presentation helpers.

  The module is imported into Blueprint schemas, so it implements its small
  path and truncation primitives locally instead of depending on the general
  `Brando.Utils` module.
  """

  @doc """
  Returns the first non-nil value, optionally stripping tags or truncating it.

  ## Examples

      iex> Brando.Blueprint.Value.fallback([nil, {:strip_tags, "<p>text</p>"}, "default"])
      "text"

      iex> Brando.Blueprint.Value.fallback([nil, nil, "default"])
      "default"

      iex> Brando.Blueprint.Value.fallback([nil, {:strip_tags, nil}, "default"])
      "default"
  """
  @spec fallback([term()]) :: term() | nil
  def fallback(values) when is_list(values) do
    Enum.reduce_while(values, nil, fn candidate, _current -> resolve_candidate(candidate) end)
  end

  @doc """
  Resolves the first non-nil path from `data`, with the same optional transforms as `fallback/1`.
  """
  @spec fallback(map() | keyword(), [term()]) :: term() | nil
  def fallback(data, paths) when is_list(paths) do
    Enum.reduce_while(paths, nil, fn path, _current ->
      {transform, keys} = path_spec(path)

      case try_path(data, List.wrap(keys)) do
        nil -> {:cont, nil}
        value -> {:halt, transform_value(value, transform)}
      end
    end)
  end

  @doc """
  Extracts plain text from an entry's rendered block field.

  Block fields keep a `rendered_<field>` column that Brando refreshes on every
  save, so this needs no preloads — which matters, since meta tags are usually
  built in a controller that only preloads images.

  The HTML is flattened with whitespace at every tag boundary (so
  `<h2>Title</h2><p>Body</p>` does not collapse into `TitleBody`), entities are
  decoded, runs of whitespace are squeezed, and the result is truncated.

  Returns `nil` when the field is empty or holds no text, so it composes with
  `fallback/1`:

      field ["description", "og:description"], fn entry ->
        fallback([entry.meta_description, rendered_text(entry)])
      end

  ## Options

    * `:length` - characters to truncate to. Defaults to `160`.
    * `:field` - block field name. Defaults to `:blocks`.

  ## Examples

      iex> Brando.Blueprint.Value.rendered_text(%{rendered_blocks: "<h2>Tittel</h2><p>Brød &amp; tekst</p>"})
      "Tittel Brød & tekst"

      iex> Brando.Blueprint.Value.rendered_text(%{rendered_blocks: "<p>  </p>"})
      nil

      iex> Brando.Blueprint.Value.rendered_text(%{rendered_blocks: nil})
      nil
  """
  @spec rendered_text(map(), keyword()) :: String.t() | nil
  def rendered_text(entry, opts \\ []) do
    field = Keyword.get(opts, :field, :blocks)
    length = Keyword.get(opts, :length, 160)

    entry
    |> Map.get(:"rendered_#{field}")
    |> flatten_html()
    |> case do
      nil -> nil
      "" -> nil
      text -> truncate(text, length)
    end
  end

  defp flatten_html(nil), do: nil

  defp flatten_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]*>/, " ")
    |> HtmlEntities.decode()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp flatten_html(_), do: nil

  @doc """
  Converts a language code to the locale expected by Open Graph consumers.
  """
  @spec encode_locale(String.t()) :: String.t()
  def encode_locale("en"), do: "en_US"
  def encode_locale("no"), do: "nb_NO"
  def encode_locale("nb"), do: "nb_NO"
  def encode_locale("nn"), do: "nn_NO"
  def encode_locale(locale), do: locale

  @doc """
  Safely traverses mixed maps, structs, lists, and keyword lists using `keys`.

  Atom and string keys read maps, atom keys read keyword lists, and integer
  keys index ordinary lists. Missing keys, invalid indexes, and attempts to
  continue through a scalar return `nil`.

  ## Examples

      iex> Brando.Blueprint.Value.try_path(%{clients: [%{cover_id: 2}]}, [:clients, 0, :cover_id])
      2

      iex> Brando.Blueprint.Value.try_path(%{clients: []}, [:clients, 0, :cover_id])
      nil
  """
  @spec try_path(map() | list() | nil, [atom() | String.t() | integer()] | nil) :: term() | nil
  def try_path(_data, nil), do: nil
  def try_path(data, keys) when is_list(keys), do: do_try_path(data, keys)

  defp do_try_path(data, []), do: data
  defp do_try_path(nil, _keys), do: nil

  defp do_try_path(map, [key | remaining_keys])
       when is_map(map) and (is_atom(key) or is_binary(key)) do
    map
    |> Map.get(key)
    |> do_try_path(remaining_keys)
  end

  defp do_try_path(list, [index | remaining_keys]) when is_list(list) and is_integer(index) do
    if Keyword.keyword?(list) do
      nil
    else
      list
      |> Enum.at(index)
      |> do_try_path(remaining_keys)
    end
  end

  defp do_try_path(keyword, [key | remaining_keys]) when is_list(keyword) and is_atom(key) do
    if Keyword.keyword?(keyword) do
      keyword
      |> Keyword.get(key)
      |> do_try_path(remaining_keys)
    end
  end

  defp do_try_path(_data, _keys), do: nil

  defp resolve_candidate({:strip_tags, nil}), do: {:cont, nil}
  defp resolve_candidate({:strip_tags, value}), do: {:halt, HtmlSanitizeEx.strip_tags(value)}
  defp resolve_candidate({:strip_tags_and_truncate, nil}), do: {:cont, nil}

  defp resolve_candidate({:strip_tags_and_truncate, value}),
    do: {:halt, value |> HtmlSanitizeEx.strip_tags() |> truncate(160)}

  defp resolve_candidate(nil), do: {:cont, nil}
  defp resolve_candidate(value), do: {:halt, value}

  defp path_spec({:strip_tags, keys}), do: {:strip_tags, keys}
  defp path_spec({:strip_tags_and_truncate, keys}), do: {:strip_tags_and_truncate, keys}
  defp path_spec(keys), do: {:identity, keys}

  defp transform_value(value, :strip_tags), do: HtmlSanitizeEx.strip_tags(value)
  defp transform_value(value, :strip_tags_and_truncate), do: value |> HtmlSanitizeEx.strip_tags() |> truncate(160)
  defp transform_value(value, :identity), do: value

  defp truncate(value, length, ellipsis \\ "...") do
    value = to_string(value)

    if String.length(value) <= length do
      value
    else
      String.slice(value, 0, length - String.length(ellipsis)) <> ellipsis
    end
  end
end
