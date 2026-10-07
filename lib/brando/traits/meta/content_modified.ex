defmodule Brando.Trait.Meta.ContentModified do
  @moduledoc """
  Keeps `content_modified_at` (`Brando.Trait.Meta`) honest: it moves only when
  an edit changes the entry's text substantially, so a typo fix, a reordering
  of blocks or a new meta description does not tell search engines the page
  was updated.

  `Brando.Query.Mutations` calls `stamp/2` on every create and update. A new
  entry is stamped when it is inserted. An update is stamped when its text
  differs from the stored text by at least a threshold number of words:
  `ceil(ratio * words before)`, kept between `min_words` and `max_words`. The
  defaults are 10%, between 5 and 20 words, so changing one word is never
  enough and adding a paragraph to a long article always is. A word that
  moved counts as unchanged. Saves made as `:system` (resaves, migrations,
  scheduled publishing) never move it.

      config :brando, Brando.Trait.Meta, substantive_change: [min_words: 5, max_words: 20, ratio: 0.1]

  The text is what the entry's form edits: its `:text`, `:textarea` and
  `:rich_text` inputs other than slugs, URIs and the meta fields
  (`Brando.AI.Context.available_fields/1`), and the rendered HTML of its block
  fields, read without tags.

  Read the date with `Brando.Blueprint.Value.modified_at/1`, which falls back
  to `edited_at` and `updated_at` for entries without it.
  """
  alias Ecto.Changeset

  @field :content_modified_at
  @defaults [min_words: 5, max_words: 20, ratio: 0.1]

  @doc """
  Stamps `changeset` with the current time when it is a new entry, or when it
  changes the entry's text substantially. Does nothing for schemas without
  the field, or for `:system` updates.
  """
  @spec stamp(Changeset.t(), term()) :: Changeset.t()
  def stamp(%Changeset{data: %schema{}} = changeset, user) do
    if tracked?(schema), do: do_stamp(changeset, schema, user), else: changeset
  end

  def stamp(changeset, _user), do: changeset

  defp do_stamp(changeset, schema, user) do
    cond do
      Changeset.get_change(changeset, @field) ->
        changeset

      new?(changeset) ->
        if Changeset.get_field(changeset, @field), do: changeset, else: put_now(changeset)

      user == :system ->
        changeset

      substantive_change?(text(schema, changeset.data), text(schema, changeset)) ->
        put_now(changeset)

      true ->
        changeset
    end
  end

  defp tracked?(schema) do
    function_exported?(schema, :__schema__, 1) and @field in schema.__schema__(:fields)
  end

  defp new?(%Changeset{data: %{__meta__: %{state: :built}}}), do: true
  defp new?(%Changeset{data: %{id: nil}}), do: true
  defp new?(_changeset), do: false

  defp put_now(changeset), do: Changeset.put_change(changeset, @field, DateTime.truncate(DateTime.utc_now(), :second))

  @doc """
  Whether `new` differs from `old` by enough words to count as an update.

      iex> Brando.Trait.Meta.ContentModified.substantive_change?("A short note.", "A short note!")
      false

      iex> Brando.Trait.Meta.ContentModified.substantive_change?("<p>Before</p>", "<p>Before</p><p>Five new words added here</p>")
      true
  """
  @spec substantive_change?(String.t() | nil, String.t() | nil) :: boolean()
  def substantive_change?(old, new) do
    old_words = words(old)
    changed_words(old_words, words(new)) >= threshold(length(old_words))
  end

  @doc """
  The entry's text, as `substantive_change?/2` compares it: the values of its
  text fields and rendered block fields, joined. `source` is the entry or a
  changeset of it.
  """
  @spec text(module(), map() | Changeset.t()) :: String.t()
  def text(schema, source) do
    schema
    |> text_fields()
    |> Enum.map(&value(source, &1))
    |> Enum.filter(&is_binary/1)
    |> Enum.join("\n")
  end

  defp value(%Changeset{} = changeset, field), do: Changeset.get_field(changeset, field)
  defp value(entry, field), do: Map.get(entry, field)

  defp text_fields(schema) do
    columns = schema.__schema__(:fields)
    block_fields = Brando.AI.Context.block_fields(schema)

    schema
    |> Brando.AI.Context.available_fields()
    |> Enum.flat_map(fn field ->
      cond do
        field == :language -> []
        field in block_fields -> [:"rendered_#{field}"]
        true -> [field]
      end
    end)
    |> Enum.filter(&(&1 in columns))
    |> Enum.uniq()
  end

  defp words(nil), do: []

  defp words(text) do
    text
    |> String.replace(~r/<[^>]*>/, " ")
    |> HtmlEntities.decode()
    |> String.downcase()
    |> then(&Regex.scan(~r/[\p{L}\p{N}]+/u, &1))
    |> List.flatten()
  end

  # Words added or removed, whichever is more; a word that only moved
  # appears on both sides and cancels out.
  defp changed_words(old, new) do
    old_counts = Enum.frequencies(old)
    new_counts = Enum.frequencies(new)

    removed = Enum.sum_by(old_counts, fn {word, count} -> max(count - Map.get(new_counts, word, 0), 0) end)
    added = Enum.sum_by(new_counts, fn {word, count} -> max(count - Map.get(old_counts, word, 0), 0) end)

    max(removed, added)
  end

  defp threshold(word_count) do
    opts = Keyword.merge(@defaults, config())

    (word_count * opts[:ratio])
    |> ceil()
    |> max(opts[:min_words])
    |> min(opts[:max_words])
  end

  defp config do
    :brando
    |> Application.get_env(Brando.Trait.Meta, [])
    |> Keyword.get(:substantive_change, [])
  end
end
