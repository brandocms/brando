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

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Transfer.{Catalog, Error}
  alias Brando.Translations
  alias Brando.Translations.Work

  # A result is sized whole, under the 24 KB the MCP endpoint and the
  # Assistant take (`Brando.MCP.Tools.result_limit/0`): the head, the other
  # items (at most @other_bytes) and the token first, the units in the rest.
  # The margin covers what is added after (`next_after`, `restarted`) and the
  # endpoint's link to its live page.
  @result_bytes 22_000
  # `Brando.MCP.Tools.result_limit/0`, which the Assistant's loop shares;
  # not called, as that would tie this module into a compile cycle
  @result_limit 24_000
  @batch_units 60
  @other_limit 40
  @other_bytes 4_000
  # other_note and other_total, beside the items
  @other_note_bytes 400
  @title_length 200

  @answer_note "Translate each unit's source into the translation's language, unit by unit by its key; a review " <>
                 "unit's current text may already be right. Where a review unit has source_previous, the source's " <>
                 "text before its change, make the smallest change to current that follows the change from " <>
                 "source_previous to source, keeping its other wording. Keep the format: html keeps every tag and attribute of " <>
                 "the source, markdown stays Markdown, and template placeholders ({{ }}, {% %}, <% %>) stay exactly " <>
                 "as they are. source_digest is the batch's token, which an answer to the batch is checked against. " <>
                 "Answer the batch with one translate operation in prepare_proposal, with this source_digest: each " <>
                 "unit's translation in texts by its key, or its key in reviewed when its text is right as it is. " <>
                 "When next_after is set, read the next batch with after: next_after, and answer it with another " <>
                 "translate operation in the same proposal."

  @doc "Runs the tool for `args` as `actor`."
  def run(args, actor) do
    schema = schema!(args["content_type"])
    entry = Catalog.load!(schema, args["id"], actor, :read)
    after_key = after_key!(args)

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
        {answerable, other} = work.units |> lock_units(schema, actor) |> Enum.split_with(&(&1.answerable or &1[:locked]))
        first? = not Work.follows?(answerable, work.positions, after_key)

        schema
        |> head(entry)
        |> Map.merge(%{
          role: "translation",
          source: %{content_type: Codec.content_type(schema), id: work.source_id, language: work.source_language},
          total: Enum.count(answerable, & &1.answerable),
          note: @answer_note
        })
        |> put_other(other, first?)
        |> put_batch(answerable, work.positions, after_key, %{
          type: to_string(schema),
          id: entry.id,
          language: work.language
        })

      {:error, _} ->
        Error.fail!(dgettext_unavailable())
    end
  end

  # A text in a field the actor may not change through a proposal is listed
  # in its place, not answerable, and left out of the batch's token: an
  # answer neither misses it nor may give it.
  defp lock_units(units, schema, actor) do
    locked =
      units
      |> Enum.filter(& &1.answerable)
      |> Enum.map(&unit_field/1)
      |> Enum.uniq()
      |> Enum.filter(&Proposals.locked_unit?(schema, &1, actor))

    Enum.map(units, fn unit ->
      if unit.answerable and unit_field(unit) in locked,
        do: locked_unit(unit),
        else: unit
    end)
  end

  defp unit_field(unit), do: unit.key |> String.split("/", parts: 2) |> hd()

  defp locked_unit(unit) do
    unit
    |> Map.take([:key, :kind, :label, :format, :block_uid])
    |> Map.merge(%{
      answerable: false,
      locked: true,
      reason:
        "This field is locked for you: only a superuser can change it, so it cannot be translated in a " <>
          "proposal. Leave it out of the answer."
    })
  end

  # Not answerable with text; listed with the first batch, as the form's work
  # list shows them
  defp put_other(result, [], _first?), do: result

  defp put_other(result, other, true) do
    listed =
      other
      |> Enum.take(@other_limit)
      |> Enum.reduce_while({[], 0}, fn item, {acc, size} ->
        size = size + byte_size(Jason.encode!(item)) + 1
        if size > @other_bytes, do: {:halt, {acc, size}}, else: {:cont, {[item | acc], size}}
      end)
      |> elem(0)
      |> Enum.reverse()

    Map.merge(result, %{
      other: listed,
      other_total: length(other),
      other_note:
        "Not answerable with text: a link waiting for its target's translation, or a value updated from the " <>
          "source. They are listed as the editor sees them, the first of other_total; they resolve in the admin."
    })
  end

  defp put_other(result, _other, false), do: result

  # The units take what the rest of the result leaves. Should the estimate
  # be short, units are left to the next batch until the result fits.
  # A unit larger than a result holds with the most other items it can have
  # is too long for any batch: `Work.batch/5` lists it without its text.
  defp put_batch(result, units, positions, after_key, scope) do
    skeleton = Map.merge(result, %{units: [], next_after: nil, source_digest: Work.token(scope, [])})
    budget = max(@result_bytes - byte_size(Jason.encode!(skeleton)), 0)
    bare = skeleton |> Map.drop([:other, :other_total, :other_note]) |> Jason.encode!() |> byte_size()
    alone = @result_bytes - bare - @other_bytes - @other_note_bytes
    batch = Work.batch(units, positions, after_key, budget, max_units: @batch_units, alone: alone)
    fit(result, Enum.reverse(batch.units), batch.more, batch, scope)
  end

  # The units last first, so the last read is at hand
  defp fit(result, reversed, more?, batch, scope) do
    units = Enum.reverse(reversed)

    full =
      result
      |> Map.merge(%{
        next_after: if(more?, do: hd(reversed).key),
        units: units,
        source_digest: Work.token(scope, units)
      })
      |> put_restarted(batch)

    case reversed do
      [_last | [_ | _] = kept] ->
        if byte_size(Jason.encode!(full)) > @result_limit,
          do: fit(result, kept, true, batch, scope),
          else: full

      _ ->
        full
    end
  end

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
        new_translation(schema, entry, head, language, after_key, actor)

      true ->
        Error.fail!(
          "#{inspect(language)} is not a language this entry can be translated into here. Use one of missing_languages."
        )
    end
  end

  defp new_translation(schema, entry, head, language, after_key, actor) do
    {:ok, %{units: all, positions: positions}} = Work.new_translation_units(schema, entry.id)
    all = lock_units(all, schema, actor)

    head
    |> Map.merge(%{
      new_translation: language,
      total: Enum.count(all, & &1.answerable),
      note:
        "The units a new #{language} translation of this entry gets, before it exists, keyed as its work " <>
          "items will be. One proposal creates and fills in the translation: create_translation with a ref R, " <>
          "then translate on {\"new\": R}. " <> @answer_note
    })
    |> put_batch(all, positions, after_key, %{type: to_string(schema), id: {:new, entry.id}, language: language})
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

  # A cursor that cannot be followed would read the first batch again and
  # again: it is refused, where an unknown key restarts and says so
  defp after_key!(%{"offset" => _}),
    do: Error.fail!("offset is not an argument. Read the next batch with after: next_after.")

  defp after_key!(%{"after" => key}) when is_binary(key) and key != "", do: key
  defp after_key!(%{"after" => key}) when key in [nil, ""], do: nil
  defp after_key!(%{"after" => _}), do: Error.fail!("after takes a unit's key, as next_after gives it.")
  defp after_key!(_args), do: nil

  # The title names the entry in every batch, so a long one is cut: its whole
  # text is a unit of its own
  defp head(schema, entry) do
    %{
      content_type: Codec.content_type(schema),
      id: entry.id,
      title: entry |> Catalog.describe() |> Map.get(:title) |> to_string() |> String.slice(0, @title_length),
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
