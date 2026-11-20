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

  @answer_note "Translate each unit's source into the translation's language and answer the batch with one " <>
                 "translate operation in prepare_proposal: its source_digest, texts {key: translation} for the units " <>
                 "you translate, and reviewed [key] for those whose current text is right as it is. Every unit of " <>
                 "the batch is answered once. Keep the format: html keeps every tag and attribute of the source, " <>
                 "markdown stays Markdown, and template placeholders ({{ }}, {% %}, <% %>) stay exactly as they " <>
                 "are. When next_offset is set, read the next batch with it."

  @doc "Runs the tool for `args` as `actor`."
  def run(args, actor) do
    schema = schema!(args["content_type"])
    entry = Catalog.load!(schema, args["id"], actor, :read)
    offset = max(integer(args["offset"]) || 0, 0)

    case Translations.synchronized?(schema) && Translations.editor_state(schema, entry.id) do
      false -> not_synchronized(schema, entry)
      nil -> source(schema, entry, args["language"], offset, actor)
      %{member: %{role: :source}} -> source(schema, entry, args["language"], offset, actor)
      %{member: %{synchronized: false}} -> independent(schema, entry)
      %{source: %{id: source_id}} -> translation(schema, entry, source_id, args["language"], offset, actor)
    end
  end

  defp translation(schema, entry, source_id, language, offset, actor) do
    readable_source!(schema, source_id, actor)
    own = to_string(entry.language)

    if language not in [nil, "", own],
      do: Error.fail!("This entry is the #{own} version. language names a new translation, on its source.")

    case Work.translation_units(schema, entry.id) do
      {:ok, work} ->
        {answerable, other} = Enum.split_with(work.units, & &1.answerable)
        {units, next} = Work.batch(answerable, offset, @batch_bytes, @batch_units)

        schema
        |> head(entry)
        |> Map.merge(%{
          role: "translation",
          source: %{content_type: Codec.content_type(schema), id: work.source_id, language: work.source_language},
          total: length(answerable),
          offset: offset,
          next_offset: next,
          units: units,
          source_digest: Work.token(%{type: to_string(schema), id: entry.id, language: work.language}, units),
          note: @answer_note
        })
        |> put_other(other, offset)

      {:error, _} ->
        Error.fail!(dgettext_unavailable())
    end
  end

  # Not answerable with text; listed with the first batch, as the form's work
  # list shows them
  defp put_other(result, [], _offset), do: result

  defp put_other(result, other, 0) do
    Map.merge(result, %{
      other: Enum.take(other, @other_limit),
      other_total: length(other),
      other_note:
        "Not answerable with text: a link waiting for its target's translation, or a value updated from the " <>
          "source. They are listed as the editor sees them; they resolve in the admin."
    })
  end

  defp put_other(result, _other, _offset), do: result

  defp source(schema, entry, language, offset, actor) do
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
            "to read the units a new translation would have: create it with create_translation and translate " <>
            "it in the same proposal."
        )

      version = Enum.find(versions, &(&1.language == language and Map.get(&1, :in_trash))) ->
        Error.fail!(
          "The #{version.language} version is in the trash. It is restored, or deleted for good, in the admin."
        )

      version = Enum.find(versions, &(&1.language == language)) ->
        Error.fail!("There is a #{language} version already: read its work with id #{version.id}.")

      language in missing ->
        new_translation(schema, entry, head, language, offset)

      true ->
        Error.fail!(
          "#{inspect(language)} is not a language this entry can be translated into here. Use one of missing_languages."
        )
    end
  end

  defp new_translation(schema, entry, head, language, offset) do
    {:ok, all} = Work.new_translation_units(schema, entry.id)
    {units, next} = Work.batch(all, offset, @batch_bytes, @batch_units)

    Map.merge(head, %{
      new_translation: language,
      total: length(all),
      offset: offset,
      next_offset: next,
      units: units,
      source_digest: Work.token(%{type: to_string(schema), id: {:new, entry.id}, language: language}, units),
      note:
        "The units a new #{language} translation of this entry gets, before it exists. Create it with " <>
          "create_translation and answer them with translate operations on {\"new\": REF} in the same proposal. " <>
          @answer_note
    })
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

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp integer(_), do: nil

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)
end
