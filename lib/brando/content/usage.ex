defmodule Brando.Content.Usage do
  @moduledoc """
  Where media is used: which entries show an image, a video, a gallery or a
  file — and where a form is, which blocks hold in a form variable. The admin shows it beside each asset so an editor can recognise what
  they are looking at and see what is safe to remove.

  Media is used from:

    * blocks — a block's refs and vars, credited to the entry that owns the
      block (see `Brando.Content.BlockReferences`)
    * page vars and global set vars
    * galleries — the images and videos among a gallery's objects
    * fields — a Blueprint's asset field of the kind, such as `cover_id`

  Lookups take the ids of one page of assets at a time, so a listing costs a
  handful of queries rather than a few per row.
  """

  import Ecto.Query

  alias Brando.Content.BlockReferences

  @type kind :: :image | :video | :gallery | :file | :form
  @type usage :: %{
          label: String.t(),
          url: String.t() | nil,
          type: String.t(),
          cover: String.t() | nil,
          status: atom() | nil,
          language: atom() | nil
        }

  @kinds [:image, :video, :gallery, :file, :form]
  @gallery Module.concat(["Brando", "Galleries", "Gallery"])
  @gallery_object Module.concat(["Brando", "Galleries", "GalleryObject"])
  @page Module.concat(["Brando", "Pages", "Page"])
  @global_set Module.concat(["Brando", "Sites", "GlobalSet"])

  @doc """
  Where each of `ids` is used. Returns `%{id => [usage]}`, sorted by label;
  ids used nowhere are left out.
  """
  @spec list(kind(), [integer()]) :: %{optional(integer()) => [usage()]}
  def list(_kind, []), do: %{}

  def list(kind, ids) when kind in @kinds do
    references = references(kind, ids)
    labels = labels(Enum.map(references, &elem(&1, 1)))

    references
    |> Enum.group_by(&elem(&1, 0), fn {_, entry} -> Map.fetch!(labels, entry) end)
    |> Map.new(fn {id, usages} -> {id, Enum.sort_by(usages, &String.downcase(&1.label))} end)
  end

  @doc """
  Puts each entry's usage in its `:usage` field. A listing's `decorate`, so
  one page costs one lookup.
  """
  @spec put([struct()], kind()) :: [struct()]
  def put(entries, kind) do
    usage = list(kind, Enum.map(entries, & &1.id))
    Enum.map(entries, &Map.put(&1, :usage, Map.get(usage, &1.id, [])))
  end

  @doc """
  The ids of every asset of `kind` that is used somewhere, for listing the
  unused ones, which the libraries offer to delete. It errs towards "used":
  an entry in the trash still uses its assets, so restoring it finds them,
  and so does an editor's unsaved copy of an entry (its recovery draft),
  where a block or field holds the asset.
  """
  @spec used_ids(kind()) :: [integer()]
  def used_ids(kind) when kind in @kinds do
    kind
    |> references(:all, include_deleted: true)
    |> Enum.map(&elem(&1, 0))
    |> Kernel.++(in_drafts(kind))
    |> Enum.uniq()
  end

  @doc """
  The entries each of `ids` belongs to, as `%{id => [{schema, entry_id}]}`.
  Unlike `list/2`, a gallery is not an owner: an image or video in one
  belongs to the entries that show the gallery. Ids no entry uses are left
  out.
  """
  @spec owners(kind(), [integer()]) :: %{optional(integer()) => [{module(), integer()}]}
  def owners(_kind, []), do: %{}

  def owners(kind, ids) when kind in @kinds do
    references = references(kind, ids)
    gallery_ids = for {_id, {@gallery, gallery_id}} <- references, uniq: true, do: gallery_id
    gallery_owners = :gallery |> references(gallery_ids) |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    references
    |> Enum.flat_map(fn
      {id, {@gallery, gallery_id}} -> Enum.map(Map.get(gallery_owners, gallery_id, []), &{id, &1})
      reference -> [reference]
    end)
    |> Enum.uniq()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "What to call each `{schema, entry_id}`: its title, admin URL, type, cover and status."
  @spec labels([{module(), integer()}]) :: %{optional({module(), integer()}) => usage()}
  def labels(entries) do
    entries = Enum.uniq(entries)

    identifiers =
      entries
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {schema, ids} ->
        from(i in Brando.Content.Identifier, where: i.schema == ^schema and i.entry_id in ^ids)
        |> Brando.Repo.all()
        |> Enum.map(&{{schema, &1.entry_id}, &1})
      end)
      |> Map.new()

    titles = titles(Enum.reject(entries, &Map.has_key?(identifiers, &1)))

    Map.new(entries, fn entry -> {entry, usage(entry, Map.get(identifiers, entry), Map.get(titles, entry))} end)
  end

  defp usage({schema, id}, identifier, title) do
    type = singular(schema)

    %{
      label: usage_label(identifier || title, type, id),
      url: admin_url(schema, id),
      type: type,
      cover: identifier && identifier.cover,
      status: identifier && identifier.status,
      language: identifier && identifier.language
    }
  end

  defp usage_label(source, type, id) do
    case source do
      %{title: title} when is_binary(title) and title != "" -> title
      title when is_binary(title) and title != "" -> URI.decode(title)
      _ -> "#{type} ##{id}"
    end
  end

  # {asset_id, {schema, entry_id}} for every place the assets are used.
  # `include_deleted: true` counts entries in the trash as users too.
  defp references(kind, ids, opts \\ [])
  defp references(_kind, [], _opts), do: []

  defp references(kind, ids, opts) do
    Enum.uniq(in_blocks(kind, ids, opts) ++ in_vars(kind, ids) ++ in_galleries(kind, ids) ++ in_fields(kind, ids, opts))
  end

  # A form is only ever in a variable, of a block or of a block's table row.
  defp in_blocks(:form, ids, opts) do
    :form |> in_block_vars(ids) |> Enum.uniq() |> credit_blocks(opts)
  end

  defp in_blocks(kind, ids, opts) do
    (by_ids(from(r in "content_refs", where: not is_nil(r.block_id)), kind, ids) ++ in_block_vars(kind, ids))
    |> Enum.uniq()
    |> credit_blocks(opts)
  end

  # {id, block_id} for each variable of a block, or of a row of a table
  # block, holding the asset: a "Downloads" table's files are in its rows.
  defp in_block_vars(kind, ids) do
    from(v in "content_vars",
      left_join: row in "content_table_rows",
      on: row.id == v.table_row_id,
      where: not is_nil(v.block_id) or not is_nil(row.block_id),
      select: {field(v, ^fk(kind)), coalesce(v.block_id, row.block_id)}
    )
    |> where_ids(fk(kind), ids)
    |> Brando.Repo.all()
  end

  # {id, block_id} to {id, entry}, for the entries owning the blocks.
  defp credit_blocks(rows, opts) do
    entries =
      rows
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> BlockReferences.list_entries_for_block_ids(include_deleted: opts[:include_deleted] == true)

    for {id, block_id} <- rows, entry <- Map.get(entries, block_id, []), do: {id, entry}
  end

  # Ids of `kind` in the current site's open recovery drafts (unsaved
  # editor copies, `Brando.Drafts`): any `<kind>_id` key, as block refs and
  # variables have, or the foreign key of a Blueprint field of the kind.
  defp in_drafts(kind) do
    now = DateTime.utc_now()
    keys = Enum.uniq([to_string(fk(kind)) | Enum.map(asset_fields(kind), &to_string(elem(&1, 1)))])

    Enum.flat_map(keys, fn key ->
      from(d in "entry_drafts",
        where:
          d.scope == ^Brando.Drafts.scope() and is_nil(d.discarded_at) and is_nil(d.resolved_at) and
            (is_nil(d.expires_at) or d.expires_at > ^now),
        select: fragment("jsonb_path_query(?, (?::text)::jsonpath) #>> '{}'", d.payload, ^~s(lax $.**."#{key}"))
      )
      # A shared table: every site's drafts are in `public`, told apart by scope.
      |> Brando.Repo.all(prefix: "public")
      |> Enum.flat_map(&draft_id/1)
    end)
  end

  defp in_vars(kind, ids) do
    pages = by_ids(from(v in "content_vars", where: not is_nil(v.page_id)), kind, ids, :page_id)
    sets = by_ids(from(v in "content_vars", where: not is_nil(v.global_set_id)), kind, ids, :global_set_id)

    Enum.map(pages, fn {id, page_id} -> {id, {@page, page_id}} end) ++
      Enum.map(sets, fn {id, set_id} -> {id, {@global_set, set_id}} end)
  end

  defp in_galleries(kind, ids) when kind in [:image, :video] do
    from(o in @gallery_object, select: {field(o, ^fk(kind)), o.gallery_id}, distinct: true)
    |> where_ids(fk(kind), ids)
    |> Brando.Repo.all()
    |> Enum.map(fn {id, gallery_id} -> {id, {@gallery, gallery_id}} end)
  end

  defp in_galleries(_kind, _ids), do: []

  defp draft_id(value) do
    case value && Integer.parse(value) do
      {id, ""} -> [id]
      _ -> []
    end
  end

  defp in_fields(kind, ids, opts) do
    for {schema, foreign_key} <- asset_fields(kind),
        {id, entry_id} <- field_references(schema, foreign_key, ids, opts),
        do: {id, {schema, entry_id}}
  end

  defp field_references(schema, foreign_key, ids, opts) do
    query = from(e in schema, select: {field(e, ^foreign_key), e.id})

    query =
      if :deleted_at in schema.__schema__(:fields) and !opts[:include_deleted],
        do: where(query, [e], is_nil(e.deleted_at)),
        else: query

    query |> where_ids(foreign_key, ids) |> Brando.Repo.all()
  end

  # Every Blueprint field holding an asset of `kind`, as {schema, foreign_key}.
  # Blueprints do not change while the system runs, so this is worked out
  # once per schema prefix: a site's environment has its own tables, and its
  # migrations can run ahead of or behind `public`'s.
  defp asset_fields(kind) do
    key = {__MODULE__, :asset_fields, Brando.Tenant.current_prefix()}

    fields =
      case :persistent_term.get(key, nil) do
        nil ->
          fields = collect_asset_fields()
          :persistent_term.put(key, fields)
          fields

        fields ->
          fields
      end

    Map.get(fields, kind, [])
  end

  defp collect_asset_fields do
    [Brando.RuntimeConfig.get(:otp_app), :brando]
    |> Enum.flat_map(fn app ->
      case :application.get_key(app, :modules) do
        {:ok, modules} -> modules
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.filter(&(Brando.Blueprint.blueprint?(&1) and is_binary(&1.__schema__(:source))))
    |> Enum.flat_map(fn schema ->
      for asset <- Brando.Blueprint.Assets.__assets__(schema),
          asset.type in @kinds,
          foreign_key = :"#{asset.name}_id",
          foreign_key in schema.__schema__(:fields),
          do: {asset.type, {schema, foreign_key}}
    end)
    |> only_existing_columns()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  # A Blueprint can declare a field its table does not have yet (a pending
  # migration); asking for that column would fail the whole lookup. Each
  # table is checked where `Brando.Repo` will query it: the current tenant's
  # schema, or `public` for a shared table and without tenancy.
  defp only_existing_columns(fields) do
    prefix = Brando.Tenant.current_prefix()

    existing =
      Ecto.Adapters.SQL.query!(
        Brando.RuntimeConfig.get(:repo_module),
        """
        SELECT table_schema, table_name, column_name FROM information_schema.columns
        WHERE table_schema IN (current_schema(), 'public', coalesce($1::text, current_schema()))
        """,
        [prefix]
      ).rows
      |> MapSet.new(fn [table_schema, table, column] -> {table_schema, table, column} end)

    {:ok, %{rows: [[current]]}} =
      Ecto.Adapters.SQL.query(Brando.RuntimeConfig.get(:repo_module), "SELECT current_schema()", [])

    Enum.filter(fields, fn {_kind, {schema, foreign_key}} ->
      table_schema = if schema.__schema__(:prefix) == "public", do: "public", else: prefix || current
      MapSet.member?(existing, {table_schema, schema.__schema__(:source), to_string(foreign_key)})
    end)
  end

  defp by_ids(query, kind, ids, via \\ :block_id) do
    query
    |> select([q], {field(q, ^fk(kind)), field(q, ^via)})
    |> where_ids(fk(kind), ids)
    |> Brando.Repo.all()
  end

  defp where_ids(query, foreign_key, :all), do: where(query, [q], not is_nil(field(q, ^foreign_key)))
  defp where_ids(query, foreign_key, ids), do: where(query, [q], field(q, ^foreign_key) in ^ids)

  defp fk(kind), do: :"#{kind}_id"

  # An entry without an identifier (a video) is named by its title field.
  defp titles(entries) do
    entries
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {schema, _} -> schema.__schema__(:type, :title) in [:string, :text] end)
    |> Enum.flat_map(fn {schema, ids} ->
      from(e in schema, where: e.id in ^ids, select: {e.id, e.title})
      |> Brando.Repo.all()
      |> Enum.map(fn {id, title} -> {{schema, id}, title} end)
    end)
    |> Map.new()
  end

  defp singular(schema) do
    Brando.Blueprint.get_singular(schema)
  rescue
    _ -> schema |> Module.split() |> List.last()
  end

  defp admin_url(schema, id) do
    schema.__admin_route__(:update, [id])
  rescue
    _ -> nil
  end
end
