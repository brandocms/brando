defmodule Brando.Content.Proposals.TranslationWork do
  @moduledoc """
  The `translation_work` tool (`Brando.Content.Proposals.Tools`): what a
  client needs to translate a synchronized entry, from
  `Brando.Translations.Work`.

    * A synchronized translation: its open work as units, in batches that
      fit a result, each batch with its `source_digest` token.
    * A synchronized source, or an entry of a synchronized type that has no
      translations yet (it becomes the source of the first): its language
      versions with their open work, and the languages without one. With
      `language` naming one of those, the units a new translation in it
      would have.
    * Anything else: what the entry is, and that it is not translated by
      synchronization.

  The actor must be allowed to read both the translation and its source; a
  source it may not read is refused as an entry that does not exist.
  Reading resyncs a translation's pending version computed against an
  older save, as opening the form does; nothing else is written.
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Transfer.{Catalog, Error}
  alias Brando.Translations
  alias Brando.Translations.Work

  # Units per result: under the MCP endpoint's 24 KB with the token, the
  # other items and the head
  @batch_bytes 14_000
  @batch_units 60
  @other_limit 40

  @answer_note "Translate each unit's source into the translation's language, unit by unit by its key; a review " <>
                 "unit's current text may already be right. Keep the format: html keeps every tag and attribute of " <>
                 "the source, markdown stays Markdown, and template placeholders ({{ }}, {% %}, <% %>) stay exactly " <>
                 "as they are. source_digest is the batch's token, which an answer to the batch is checked against. " <>
                 "When next_after is set, read the next batch with after: next_after."

  @doc "Runs the tool for `args` as `actor`."
  def run(args, actor) do
    schema = schema!(args["content_type"])
    entry = Catalog.load!(schema, args["id"], actor, :read)
    after_key = if is_binary(args["after"]) and args["after"] != "", do: args["after"]

    case Translations.synchronized?(schema) && Translations.editor_state(schema, entry.id) do
      false -> not_synchronized(schema, entry)
      nil -> source(schema, entry, args["language"], after_key, actor)
      %{member: %{role: :source}} -> source(schema, entry, args["language"], after_key, actor)
      %{member: %{synchronized: false}} -> independent(schema, entry)
      %{source: %{id: source_id}} -> translation(schema, entry, source_id, args["language"], after_key, actor)
    end
  end

  defp translation(schema, entry, source_id, language, after_key, actor) do
    readable_source!(schema, source_id, actor)
    own = to_string(entry.language)

    if language not in [nil, "", own],
      do: Error.fail!("This entry is the #{own} version. language names a new translation, on its source.")

    case Work.translation_units(schema, entry.id) do
      {:ok, work} ->
        {answerable, other} = Enum.split_with(work.units, & &1.answerable)
        batch = Work.batch(answerable, work.positions, after_key, @batch_bytes, max_units: @batch_units)

        schema
        |> head(entry)
        |> Map.merge(%{
          role: "translation",
          source: %{content_type: Codec.content_type(schema), id: work.source_id, language: work.source_language},
          total: length(answerable),
          next_after: next_after(batch),
          units: batch.units,
          source_digest: Work.token(%{type: to_string(schema), id: entry.id, language: work.language}, batch.units),
          note: @answer_note
        })
        |> put_restarted(batch)
        |> put_other(other, after_key == nil or batch.restarted)

      {:error, _} ->
        Error.fail!(dgettext_unavailable())
    end
  end

  # Not answerable with text; listed with the first batch, as the form's work
  # list shows them
  defp put_other(result, [], _first?), do: result

  defp put_other(result, other, true) do
    Map.merge(result, %{
      other: Enum.take(other, @other_limit),
      other_total: length(other),
      other_note:
        "Not answerable with text: a link waiting for its target's translation, or a value updated from the " <>
          "source. They are listed as the editor sees them; they resolve in the admin."
    })
  end

  defp put_other(result, _other, false), do: result

  defp next_after(%{more: true, units: units}), do: List.last(units).key
  defp next_after(_batch), do: nil

  defp put_restarted(result, %{restarted: true}) do
    Map.merge(result, %{
      restarted: true,
      restarted_note: "after named a key this entry no longer has: this batch starts from the beginning."
    })
  end

  defp put_restarted(result, _batch), do: result

  defp source(schema, entry, language, after_key, actor) do
    missing = Translations.missing_languages(schema, entry)

    listed =
      schema
      |> Translations.listing_status([entry], actor)
      |> Map.get(entry.id, [])
      |> Enum.reject(&(&1.entry_id == entry.id))

    trashed = trashed_ids(schema, Enum.map(listed, & &1.entry_id))

    # A version in the trash still holds its language; its work is read once
    # it is restored
    versions =
      Enum.map(listed, fn version ->
        if version.entry_id in trashed,
          do: %{language: version.language, id: version.entry_id, in_trash: true},
          else: %{
            language: version.language,
            id: version.entry_id,
            synchronized: version.synchronized,
            open: version.counts
          }
      end)

    head = Map.merge(head(schema, entry), %{role: "source", versions: versions, missing_languages: missing})

    cond do
      language in [nil, ""] ->
        Map.put(
          head,
          :note,
          "Read a version's work with its id; a version in_trash has none until it is restored. For a language in missing_languages, call again with language " <>
            "to read the units a new translation would have."
        )

      version = Enum.find(versions, &(&1.language == language and Map.get(&1, :in_trash))) ->
        Error.fail!("The #{version.language} version is in the trash. It is restored, or deleted for good, in the admin.")

      version = Enum.find(versions, &(&1.language == language)) ->
        Error.fail!("There is a #{language} version already: read its work with id #{version.id}.")

      language in missing ->
        new_translation(schema, entry, head, language, after_key)

      true ->
        Error.fail!(
          "#{inspect(language)} is not a language this entry can be translated into here. Use one of missing_languages."
        )
    end
  end

  defp new_translation(schema, entry, head, language, after_key) do
    {:ok, %{units: all, positions: positions}} = Work.new_translation_units(schema, entry.id)
    batch = Work.batch(all, positions, after_key, @batch_bytes, max_units: @batch_units)

    head
    |> Map.merge(%{
      new_translation: language,
      total: length(all),
      next_after: next_after(batch),
      units: batch.units,
      source_digest: Work.token(%{type: to_string(schema), id: {:new, entry.id}, language: language}, batch.units),
      note:
        "The units a new #{language} translation of this entry gets, before it exists, keyed as its work " <>
          "items will be. " <> @answer_note
    })
    |> put_restarted(batch)
  end

  defp trashed_ids(schema, ids) do
    if ids != [] and :deleted_at in schema.__schema__(:fields) do
      from(e in schema, where: e.id in ^ids and not is_nil(e.deleted_at), select: e.id)
      |> Brando.Repo.all()
    else
      []
    end
  end

  defp not_synchronized(schema, entry) do
    schema
    |> head(entry)
    |> Map.merge(%{
      synchronized: false,
      message:
        "#{Codec.content_type(schema)} is not synchronized: its language versions are separate entries, with no " <>
          "translation work. Change a version's text with set_fields and set_block_text."
    })
  end

  defp independent(schema, entry) do
    schema
    |> head(entry)
    |> Map.merge(%{
      synchronized: false,
      message:
        "This #{entry.language} version is independent: it no longer follows its source, and has no " <>
          "translation work. Change its text with set_fields and set_block_text."
    })
  end

  defp head(schema, entry) do
    %{
      content_type: Codec.content_type(schema),
      id: entry.id,
      title: Catalog.describe(entry).title,
      language: entry |> Map.get(:language) |> to_string_or_nil()
    }
  end

  # The source's text is in every unit: without read on it, it is as if the
  # translation had none
  defp readable_source!(schema, source_id, actor) do
    case Error.protect(fn -> Catalog.load!(schema, source_id, actor, :read) end) do
      {:ok, _source} -> :ok
      {:error, _} -> Error.fail!(dgettext_unavailable())
    end
  end

  defp dgettext_unavailable, do: dgettext("content_transfer", "The selected entry is no longer available.")

  defp schema!(name) do
    case Codec.schema(name) do
      {:ok, schema} -> schema
      :error -> Error.fail!("Unknown content type #{inspect(name)}. Use list_content_types.")
    end
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)
end
