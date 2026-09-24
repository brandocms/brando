defmodule Brando.SEO.ContentStats do
  @moduledoc """
  Measures entries' rendered block HTML inside the database, so the audit
  never has to load it: words of visible text, the heading levels in
  document order, and the alt text of every image.

  Also reads the same measurements for an entry's published language
  versions (`Brando.Trait.Translatable` alternates), which is what the
  translation parity check compares against.

  The HTML is matched with regular expressions rather than parsed. That is
  enough for markup Brando rendered itself; it is not a general HTML parser.
  """
  import Ecto.Query, only: [from: 2]

  @type t :: %__MODULE__{words: non_neg_integer(), headings: [1..6], image_alts: [String.t() | nil]}
  defstruct words: 0, headings: [], image_alts: []

  @type alternate :: %{
          id: term(),
          language: String.t(),
          stats: t() | nil,
          edited_at: NaiveDateTime.t() | DateTime.t() | nil
        }

  # Words: tags and entities become spaces, and only tokens with a letter or
  # digit count, so a lone dash or bullet is not a word.
  defmacrop word_count(html) do
    quote do
      fragment(
        "(SELECT count(*) FROM regexp_split_to_table(regexp_replace(regexp_replace(coalesce(?, ''), '<[^>]*>', ' ', 'g'), '&[#[:alnum:]]+;', ' ', 'g'), '\\s+') AS w WHERE w ~ '[[:alnum:]]')",
        unquote(html)
      )
    end
  end

  # Heading tags in document order, as "h1".."h6".
  defmacrop headings(html) do
    quote do
      fragment(
        "ARRAY(SELECT lower(m[1]) FROM regexp_matches(coalesce(?, ''), '<(h[1-6])[\\s/>]', 'gi') AS m)",
        unquote(html)
      )
    end
  end

  # One element per <img>: its alt attribute, or NULL when it has none.
  defmacrop image_alts(html) do
    quote do
      fragment(
        "ARRAY(SELECT substring(coalesce(m[1], '') from '[\\s]alt\\s*=\\s*\"([^\"]*)\"') FROM regexp_matches(coalesce(?, ''), '<img([\\s/][^>]*)\\?>', 'gi') AS m)",
        unquote(html)
      )
    end
  end

  @doc """
  Stats for the entries `ids` of `schema`, keyed by id. Every block field's
  rendered column counts. Empty when the schema has no block fields.
  """
  @spec for_ids(module(), [term()]) :: %{term() => t()}
  def for_ids(_schema, []), do: %{}

  def for_ids(schema, ids) do
    schema
    |> rendered_columns()
    |> Enum.flat_map(fn column ->
      Brando.Repo.all(
        from e in schema,
          where: e.id in ^ids,
          select: {e.id, word_count(field(e, ^column)), headings(field(e, ^column)), image_alts(field(e, ^column))}
      )
    end)
    |> Enum.reduce(%{}, fn {id, words, headings, alts}, acc ->
      stats = %__MODULE__{words: words, headings: Enum.map(headings, &level/1), image_alts: alts}
      Map.update(acc, id, stats, &merge(&1, stats))
    end)
  end

  @doc """
  The published language versions of each of `ids`, with their stats and
  when they were last edited. Empty for schemas without alternates.
  """
  @spec alternates(module(), [term()]) :: %{term() => [alternate()]}
  def alternates(_schema, []), do: %{}

  def alternates(schema, ids) do
    if has_alternates?(schema) do
      links = linked_entries(schema, ids)
      stats = for_ids(schema, links |> Enum.map(& &1.linked_id) |> Enum.uniq())

      Enum.group_by(
        links,
        & &1.entry_id,
        &%{
          id: &1.linked_id,
          language: to_string(&1.language),
          stats: Map.get(stats, &1.linked_id),
          edited_at: &1.edited_at
        }
      )
    else
      %{}
    end
  end

  @doc "When `entry` was last edited by a person, or last updated when that is not recorded."
  @spec edited_at(map()) :: NaiveDateTime.t() | DateTime.t() | nil
  def edited_at(entry), do: Map.get(entry, :edited_at) || Map.get(entry, :updated_at)

  defp linked_entries(schema, ids) do
    alternate = Module.concat(schema, Alternate)
    fields = schema.__schema__(:fields)

    query =
      from a in alternate,
        join: l in ^schema,
        on: l.id == a.linked_entry_id,
        where: a.entry_id in ^ids,
        select: %{entry_id: a.entry_id, linked_id: l.id, language: l.language, updated_at: l.updated_at}

    query = if :deleted_at in fields, do: from([a, l] in query, where: is_nil(l.deleted_at)), else: query
    query = if :status in fields, do: from([a, l] in query, where: l.status == ^:published), else: query

    query =
      if :edited_at in fields,
        do: from([a, l] in query, select_merge: %{edited_at: l.edited_at}),
        else: query

    query
    |> Brando.Repo.all()
    |> Enum.map(&Map.put(&1, :edited_at, edited_at(&1)))
  end

  defp has_alternates?(schema) do
    schema.has_trait(Brando.Trait.Translatable) and function_exported?(schema, :has_alternates?, 0) and
      schema.has_alternates?() and Code.ensure_loaded?(Module.concat(schema, Alternate))
  end

  defp rendered_columns(schema) do
    columns = schema.__schema__(:fields)

    schema
    |> Brando.AI.Context.block_fields()
    |> Enum.map(&:"rendered_#{&1}")
    |> Enum.filter(&(&1 in columns))
  end

  defp merge(a, b) do
    %__MODULE__{words: a.words + b.words, headings: a.headings ++ b.headings, image_alts: a.image_alts ++ b.image_alts}
  end

  defp level("h" <> n), do: String.to_integer(n)
end
