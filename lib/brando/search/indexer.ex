defmodule Brando.Search.Indexer do
  @moduledoc """
  Builds search documents from entries and writes them (`Brando.Search`).

  Documents are written with one statement per batch: the text goes in as
  arrays and Postgres builds each `tsvector` with the document's own text
  search configuration. Every query runs in a savepoint when there is a
  surrounding transaction (Oban's inline testing mode indexes inside the
  save), so a failure here never aborts the save.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.ContentEvents
  alias Brando.Repo
  alias Brando.Search
  alias Brando.Search.Document
  alias Brando.Search.Text

  require Logger

  @batch 100

  @doc "Reads `schema` entry `id` and writes its document, or removes it."
  @spec index(module(), integer()) :: :ok
  def index(schema, id) do
    case load(schema, [id]) do
      [entry] ->
        if live?(entry), do: write(build_all(schema, [entry])), else: remove(schema, [id])
        :ok

      [] ->
        remove(schema, [id])
    end
  end

  @doc """
  Indexes every entry of `schemas` again, in batches, and removes every
  other document. Returns `{:ok, count}`, the number of documents written.
  """
  @spec rebuild([module()], (non_neg_integer(), non_neg_integer() -> any())) :: {:ok, non_neg_integer()}
  def rebuild(schemas, progress) do
    started = Repo.repo().query!("SELECT clock_timestamp()::timestamp", [], savepoint()).rows |> hd() |> hd()
    counts = Enum.flat_map(schemas, &count/1)
    total = counts |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    schemas = Enum.map(counts, &elem(&1, 0))
    progress.(0, total)

    written =
      Enum.reduce(schemas, 0, fn schema, done ->
        rebuild_schema(schema, nil, done, total, progress)
      end)

    Repo.delete_all(
      from(d in Document, where: d.indexed_at < ^started or d.schema not in ^schemas),
      savepoint()
    )

    progress.(total, total)
    {:ok, written}
  end

  defp rebuild_schema(schema, after_id, done, total, progress) do
    ids =
      Repo.all(
        from(e in live_query(schema), where: ^after_clause(after_id), order_by: [asc: e.id], limit: @batch, select: e.id),
        savepoint()
      )

    case ids do
      [] ->
        done

      ids ->
        written = schema |> load(ids) |> Enum.filter(&live?/1) |> then(&build_all(schema, &1)) |> write()
        done = done + written
        progress.(min(done, total), total)
        rebuild_schema(schema, List.last(ids), done, total, progress)
    end
  end

  defp after_clause(nil), do: true
  defp after_clause(id), do: Ecto.Query.dynamic([e], e.id > ^id)

  # A content type whose table is missing (not migrated yet) is skipped
  defp count(schema) do
    [{schema, Repo.aggregate(live_query(schema), :count, savepoint())}]
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :undefined_table do
        Logger.warning("[Brando.Search] Skipping #{inspect(schema)}: its table is missing")
        []
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp live_query(schema) do
    if :deleted_at in schema.__schema__(:fields),
      do: from(e in schema, where: is_nil(e.deleted_at)),
      else: Ecto.Queryable.to_query(schema)
  end

  defp live?(entry), do: is_nil(Map.get(entry, :deleted_at))

  defp load(schema, ids) do
    entries = Repo.all(from(e in schema, where: e.id in ^ids), savepoint())
    # Assets, relations and identifiers (for the title and cover) and blocks
    Repo.preload(entries, Brando.Blueprint.preloads_for(schema), savepoint())
  end

  ## Building

  @doc """
  The document for an entry, as the map that is written: the identifier's
  title, status, language and cover, the slugs, the meta description and
  the body text.
  """
  @spec build(module(), struct(), [atom()]) :: map()
  def build(schema, entry, text_fields \\ nil) do
    identifier = schema.__identifier__(entry)

    language =
      to_string(identifier.language || Map.get(entry, :language) || Brando.config(:default_language) || "")

    %{
      schema: to_string(schema),
      entry_id: entry.id,
      language: language,
      config: Search.config_for(language),
      title: Text.title(identifier.title),
      slug: slug(schema, entry),
      description: description(entry),
      body: Text.body(entry, text_fields || Text.text_fields(schema), language),
      status: status(identifier.status),
      cover: identifier.cover,
      updated_at: updated_at(identifier.updated_at || Map.get(entry, :updated_at))
    }
  end

  # An entry that cannot be built (its identifier template raises, say) is
  # logged and left out; the others are written.
  defp build_all(schema, entries) do
    fields = Text.text_fields(schema)

    Enum.flat_map(entries, fn entry ->
      try do
        [build(schema, entry, fields)]
      rescue
        error ->
          Logger.warning("[Brando.Search] Could not index #{inspect(schema)} ##{entry.id}: " <> Exception.message(error))
          []
      end
    end)
  end

  defp slug(schema, entry) do
    names = Enum.map(schema.__slug_fields__(), & &1.name)
    names = if :uri in schema.__schema__(:fields), do: names ++ [:uri], else: names

    names
    |> Enum.map(&Map.get(entry, &1))
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.join(" ")
    |> Text.cap(2_000)
  end

  defp description(entry) do
    case Map.get(entry, :meta_description) do
      value when is_binary(value) -> value |> Text.plain() |> Text.cap(5_000)
      _ -> nil
    end
  end

  defp status(nil), do: nil

  defp status(status) do
    case Brando.Type.Status.dump(status) do
      {:ok, code} -> code
      _ -> nil
    end
  end

  defp updated_at(%DateTime{} = at), do: at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
  defp updated_at(%NaiveDateTime{} = at), do: NaiveDateTime.truncate(at, :second)
  defp updated_at(_), do: nil

  ## Writing

  @columns ~w(schema entry_id language config title slug description body status cover updated_at)a

  @doc "Writes documents (maps from `build/3`). Returns how many were written."
  @spec write([map()]) :: non_neg_integer()
  def write([]), do: 0

  def write(documents) do
    documents = Enum.uniq_by(documents, &{&1.schema, &1.entry_id, &1.language})
    params = Enum.map(@columns, fn column -> Enum.map(documents, &Map.get(&1, column)) end)

    # An entry whose language changed leaves no document in the old one
    Repo.repo().query!(
      """
      DELETE FROM #{table()} AS d
      USING unnest($1::text[], $2::bigint[], $3::text[]) AS u(schema, entry_id, language)
      WHERE d.schema = u.schema AND d.entry_id = u.entry_id AND d.language <> u.language
      """,
      Enum.take(params, 3),
      savepoint()
    )

    %{num_rows: count} =
      Repo.repo().query!(
        """
        INSERT INTO #{table()} AS d
          (schema, entry_id, language, config, title, slug, description, body, status, cover, updated_at, indexed_at, document)
        SELECT u.schema, u.entry_id, u.language, u.config, u.title, u.slug, u.description, u.body, u.status, u.cover,
               u.updated_at, clock_timestamp(),
               setweight(to_tsvector(u.config::regconfig, coalesce(u.title, '')), 'A') ||
               setweight(to_tsvector(u.config::regconfig,
                 coalesce(translate(u.slug, '/_.', '   '), '') || ' ' || coalesce(u.description, '')), 'B') ||
               setweight(to_tsvector(u.config::regconfig, coalesce(u.body, '')), 'C')
        FROM unnest($1::text[], $2::bigint[], $3::text[], $4::text[], $5::text[], $6::text[], $7::text[],
                    $8::text[], $9::integer[], $10::text[], $11::timestamp[])
          AS u(schema, entry_id, language, config, title, slug, description, body, status, cover, updated_at)
        ON CONFLICT (schema, entry_id, language) DO UPDATE SET
          config = excluded.config, title = excluded.title, slug = excluded.slug,
          description = excluded.description, body = excluded.body, status = excluded.status,
          cover = excluded.cover, updated_at = excluded.updated_at, indexed_at = excluded.indexed_at,
          document = excluded.document
        """,
        params,
        savepoint()
      )

    count
  end

  defp remove(schema, ids) do
    Repo.delete_all(from(d in Document, where: d.schema == ^schema and d.entry_id in ^ids), savepoint())
    :ok
  end

  # The table in the current site and environment's schema
  defp table do
    case Brando.Tenant.current_prefix() do
      nil ->
        "search_documents"

      prefix ->
        if Brando.Tenant.valid_prefix?(prefix),
          do: ~s("#{prefix}".search_documents),
          else: raise(ArgumentError, "invalid tenant prefix")
    end
  end

  defp savepoint, do: ContentEvents.savepoint()
end
