defmodule Brando.Tenant.SchemaImport do
  @moduledoc """
  Copies a site from a schema that holds a restored copy of another
  installation's `public` schema into a new site's Production schema.

  The source schema is only read: it is checked, its users are read for the
  user mapping, and its tenant tables are dumped with `pg_dump --data-only`.
  Everything else happens in the target schema.

  ## Users

  Users stay this installation's: the source's `users` table and the other
  shared tables (`Brando.Tenant.SharedTables`) are not copied. Every reference
  to a user in the copied rows is remapped (`user_mapping/2`): a source user
  whose email matches a user here, ignoring case, becomes that user, and every
  other one becomes the creator.

  The references are found from the target's foreign keys to `public.users`,
  plus the user ids Brando stores without one:

    * `content_markdown_events.actor_id`, remapped like a foreign key;
    * `notification_routes.recipient_ids`, where a recipient with no match
      here is dropped rather than replaced by the creator;
    * the entry snapshots in `revisions.encoded_entry` and
      `translation_pending_versions.payload`, whose user fields (the names of
      the foreign key columns, such as `creator_id`) are remapped, so that
      restoring a revision does not write a source user's id. A snapshot that
      cannot be decoded here is left as it is and counted in the report;
    * the block rows kept in `content_block_archive.data`.

  A row whose user column is part of a unique index (saved listing views,
  listing defaults, note mentions, notification deliveries) belongs to that
  user: for a user with no match here it is deleted, since giving every such
  row to the creator would collide.

  ## What could act on the outside world

  The copy carries settings that call other systems. They are made inert in
  the copy and named in the report (`t:report/0`):

    * webhooks and notification routes are paused (reason `:manual`, so going
      live does not resume them). Their secrets were encrypted with the source
      installation's `Brando.Crypto` secret and do not decrypt here unless
      the two share it;
    * markdown sources are disabled, so they do not pull from a repository;
    * IndexNow is disabled, so URLs are not submitted to search engines;
    * a video at a provider is marked `imported`, so deleting it here leaves it
      at the provider, where the source still plays it.

  Deploy targets live in the shared `sites` registry and are not copied: the
  new site delivers dynamically until an operator configures one. Oban jobs
  are shared and not copied either, so a scheduled revision's job stays with
  the source (the report counts them), while `publish_at` and `unpublish_at`
  dates are carried out by `Brando.Worker.ScheduledPublishingSweep`.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.SchemaCloner.Postgres, as: SchemaCloner
  alias Brando.Environments.StructureCloner.Postgres, as: StructureCloner
  alias Brando.Tenant.SharedTables
  alias Brando.Users.User
  alias Ecto.Adapters.SQL

  @template "public"
  @source_format ~r/^[a-z0-9_]+$/
  @reserved_schemas ~w(public information_schema)

  @snapshot_columns [{"revisions", "encoded_entry"}, {"translation_pending_versions", "payload"}]
  @json_columns [{"content_block_archive", "data"}]
  @unforeigned_columns [{"content_markdown_events", "actor_id"}]
  @provider_video_types ~w(mux bunny cloudflare vimeo_account)

  @typedoc "One source user and the user here it becomes."
  @type mapping_entry :: %{
          source_id: integer(),
          source_email: String.t() | nil,
          target_id: integer(),
          target_email: String.t(),
          matched: boolean()
        }

  @typedoc "One line of the closing report: what was found, how many, and what was done."
  @type report_item :: %{key: atom(), count: non_neg_integer(), action: :neutralised | :check}

  @type report :: [report_item()]

  @doc """
  Checks that `schema` can be a source: a name of lower-case letters, digits
  and underscores, not `public`, not a site's schema, existing, with a
  `users` table.
  """
  @spec validate_source(String.t()) :: :ok | {:error, term()}
  def validate_source(schema) do
    cond do
      not (is_binary(schema) and Regex.match?(@source_format, schema) and byte_size(schema) <= 63) ->
        {:error, {:invalid_source_schema, schema}}

      schema in @reserved_schemas or String.starts_with?(schema, ["tenant_", "pg_"]) ->
        {:error, {:reserved_source_schema, schema}}

      not schema_exists?(schema) ->
        {:error, {:source_schema_not_found, schema}}

      not table_exists?(schema, "users") ->
        {:error, {:source_users_table_missing, schema}}

      true ->
        :ok
    end
  end

  @doc """
  Compares the source's tenant tables with this installation's (`public`'s).

  Returns `{:error, {:source_structure_differs, differences}}` when a table or
  column is missing on either side or a column's type differs. Each difference
  is `{:missing_table, table}` (here, not in the source), `{:extra_table, table}`
  (in the source, not here), `{:missing_column, table, column}`,
  `{:extra_column, table, column}` or `{:type_differs, table, column,
  source_type, type_here}`.
  """
  @spec compare(String.t()) :: :ok | {:error, term()}
  def compare(source) do
    with {:ok, here} <- columns(@template),
         {:ok, there} <- columns(source) do
      case differences(normalise(there, source), normalise(here, @template)) do
        [] -> :ok
        differences -> {:error, {:source_structure_differs, differences}}
      end
    end
  end

  @doc "Formats `compare/1`'s differences, one per line."
  @spec format_differences([tuple()]) :: String.t()
  def format_differences(differences) do
    Enum.map_join(differences, "\n", fn
      {:missing_table, table} -> "  table #{table}: missing in the source"
      {:extra_table, table} -> "  table #{table}: only in the source"
      {:missing_column, table, column} -> "  column #{table}.#{column}: missing in the source"
      {:extra_column, table, column} -> "  column #{table}.#{column}: only in the source"
      {:type_differs, table, column, there, here} -> "  column #{table}.#{column}: #{there} in the source, #{here} here"
    end)
  end

  @doc """
  Maps every user in the source's `users` table to a user here: the one whose
  email matches, ignoring case, or `creator`. Creates no user.
  """
  @spec user_mapping(String.t(), User.t()) :: {:ok, [mapping_entry()]} | {:error, term()}
  def user_mapping(source, %User{} = creator) do
    with :ok <- validate_source(source),
         {:ok, %{rows: source_users}} <- query(~s|SELECT id, email FROM "#{source}"."users" ORDER BY id|) do
      local =
        from(u in User,
          where: is_nil(u.deleted_at),
          order_by: [asc: u.id],
          select: {fragment("lower(?)", u.email), u.id, u.email}
        )
        |> Brando.Repo.all(prefix: "public")
        |> Enum.reduce(%{}, fn {lower, id, email}, acc -> Map.put_new(acc, lower, {id, email}) end)

      {:ok, Enum.map(source_users, &map_user(&1, local, creator))}
    end
  end

  defp map_user([id, email], local, creator) do
    case is_binary(email) && Map.get(local, String.downcase(email)) do
      {target_id, target_email} ->
        %{source_id: id, source_email: email, target_id: target_id, target_email: target_email, matched: true}

      _ ->
        %{source_id: id, source_email: email, target_id: creator.id, target_email: creator.email, matched: false}
    end
  end

  @doc """
  Copies the source's tenant tables into `target`, remaps their user
  references with `mapping` (unmatched ones to `creator_id`), neutralises what
  could act on the outside world, and returns the report. Writes only to
  `target`.
  """
  @spec copy(String.t(), String.t(), [mapping_entry()], integer()) :: {:ok, report()} | {:error, term()}
  def copy(source, target, mapping, creator_id) do
    with :ok <- validate_source(source),
         {:ok, tables} <- copyable_tables(source, target),
         {:ok, references} <- user_references(target),
         :ok <- drop_constraints(target, references),
         {:ok, dump} <- SchemaCloner.dump_schema(source, dump_args(source, tables)),
         {:ok, rewritten} <- SchemaCloner.rewrite_schema(dump, source, target),
         :ok <- SchemaCloner.restore_dump(rewritten) do
      transaction(fn ->
        remap_references!(target, references, mapping, creator_id)
        remap_unforeigned!(target, references, creator_id)
        undecoded = remap_snapshots!(target, references, mapping, creator_id)
        remap_json!(target, references, mapping, creator_id)
        add_constraints!(target, references)
        advance_sequences!(target)
        neutralised = neutralise!(target)
        neutralised ++ to_check!(target, undecoded)
      end)
    end
  end

  ## Structure

  defp columns(schema) do
    sql = """
    SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod)
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    JOIN pg_attribute AS a ON a.attrelid = c.oid
    WHERE n.nspname = $1 AND c.relkind IN ('r', 'p') AND a.attnum > 0 AND NOT a.attisdropped
    ORDER BY c.relname, a.attnum
    """

    with {:ok, %{rows: rows}} <- query(sql, [schema]) do
      {:ok, Enum.reject(rows, fn [table | _] -> SharedTables.member?(table) end)}
    end
  end

  # A type in the schema itself (an enum) is qualified with that schema
  defp normalise(rows, schema) do
    qualifier = ~r/^("#{Regex.escape(schema)}"|#{Regex.escape(schema)})\./

    Enum.reduce(rows, %{}, fn [table, column, type], acc ->
      Map.update(
        acc,
        table,
        %{column => String.replace(type, qualifier, "")},
        &Map.put(&1, column, String.replace(type, qualifier, ""))
      )
    end)
  end

  defp differences(there, here) do
    tables = (Map.keys(there) ++ Map.keys(here)) |> Enum.uniq() |> Enum.sort()

    Enum.flat_map(tables, fn table ->
      case {Map.get(there, table), Map.get(here, table)} do
        {nil, _} -> [{:missing_table, table}]
        {_, nil} -> [{:extra_table, table}]
        {source_columns, columns} -> column_differences(table, source_columns, columns)
      end
    end)
  end

  defp column_differences(table, there, here) do
    (Map.keys(there) ++ Map.keys(here))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn column ->
      case {Map.get(there, column), Map.get(here, column)} do
        {nil, _} -> [{:missing_column, table, column}]
        {_, nil} -> [{:extra_column, table, column}]
        {same, same} -> []
        {source_type, type} -> [{:type_differs, table, column, source_type, type}]
      end
    end)
  end

  ## Data

  defp copyable_tables(source, target) do
    sql = """
    SELECT target.tablename
    FROM pg_tables AS target
    JOIN pg_tables AS source ON source.tablename = target.tablename AND source.schemaname = $1
    WHERE target.schemaname = $2
    ORDER BY target.tablename
    """

    with {:ok, %{rows: rows}} <- query(sql, [source, target]) do
      case rows |> Enum.map(&List.first/1) |> Enum.reject(&SharedTables.member?/1) do
        [] -> {:error, :no_copyable_tables}
        tables -> {:ok, tables}
      end
    end
  end

  defp dump_args(source, tables) do
    schema = StructureCloner.quote_identifier(source)
    ["--data-only"] ++ Enum.map(tables, &"--table=#{schema}.#{StructureCloner.quote_identifier(&1)}")
  end

  # Every single-column foreign key in `target` to `public.users`, with its
  # definition to restore it, and whether the column is part of a unique index
  # (a row that belongs to its user).
  defp user_references(target) do
    sql = """
    SELECT r.relname, a.attname, c.conname, pg_get_constraintdef(c.oid),
      EXISTS (
        SELECT 1 FROM pg_index AS i
        WHERE i.indrelid = c.conrelid AND i.indisunique AND NOT i.indisprimary
          AND (a.attnum = ANY(i.indkey)
            OR coalesce(pg_get_expr(i.indexprs, i.indrelid), '') ~ ('\\m' || a.attname || '\\M'))
      )
    FROM pg_constraint AS c
    JOIN pg_namespace AS n ON n.oid = c.connamespace
    JOIN pg_class AS r ON r.oid = c.conrelid
    JOIN pg_attribute AS a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND n.nspname = $1 AND c.confrelid = 'public.users'::regclass
      AND array_length(c.conkey, 1) = 1
    ORDER BY r.relname, a.attname
    """

    with {:ok, %{rows: rows}} <- query(sql, [target]) do
      {:ok,
       Enum.map(rows, fn [table, column, name, definition, personal] ->
         %{table: table, column: column, name: name, definition: definition, personal: personal}
       end)}
    end
  end

  defp drop_constraints(target, references) do
    Enum.reduce_while(references, :ok, fn ref, :ok ->
      case query(~s|ALTER TABLE "#{target}"."#{ref.table}" DROP CONSTRAINT "#{ref.name}"|) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:drop_user_constraint_failed, ref.name, reason}}}
      end
    end)
  end

  defp add_constraints!(target, references) do
    Enum.each(references, fn ref ->
      query!(~s|ALTER TABLE "#{target}"."#{ref.table}" ADD CONSTRAINT "#{ref.name}" #{ref.definition}|)
    end)
  end

  defp remap_references!(target, references, mapping, creator_id) do
    create_mapping_table!(mapping)

    Enum.each(references, fn %{table: table, column: column, personal: personal} ->
      remap_column!(target, table, column, personal, creator_id)
    end)
  end

  defp create_mapping_table!(mapping) do
    query!(
      "CREATE TEMPORARY TABLE brando_import_users (source_id bigint PRIMARY KEY, target_id bigint NOT NULL, matched boolean NOT NULL) ON COMMIT DROP"
    )

    mapping
    |> Enum.chunk_every(1000)
    |> Enum.each(fn chunk ->
      query!(
        "INSERT INTO pg_temp.brando_import_users SELECT * FROM unnest($1::bigint[], $2::bigint[], $3::boolean[])",
        [Enum.map(chunk, & &1.source_id), Enum.map(chunk, & &1.target_id), Enum.map(chunk, & &1.matched)]
      )
    end)
  end

  # A personal row of a user with no match here is deleted; every other
  # reference becomes its match or the creator, an id not in the source's
  # users table included.
  defp remap_column!(target, table, column, true, _creator_id) do
    qualified = ~s|"#{target}"."#{table}"|

    query!("""
    DELETE FROM #{qualified} AS t
    WHERE t."#{column}" IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM pg_temp.brando_import_users AS m WHERE m.source_id = t."#{column}" AND m.matched)
    """)

    query!("""
    UPDATE #{qualified} AS t SET "#{column}" = m.target_id
    FROM pg_temp.brando_import_users AS m
    WHERE m.source_id = t."#{column}"
    """)
  end

  defp remap_column!(target, table, column, false, creator_id) do
    query!(
      """
      UPDATE "#{target}"."#{table}" AS t
      SET "#{column}" = coalesce((SELECT m.target_id FROM pg_temp.brando_import_users AS m WHERE m.source_id = t."#{column}"), $1)
      WHERE t."#{column}" IS NOT NULL
      """,
      [creator_id]
    )
  end

  # Once one of these has a foreign key, it was remapped with the others
  defp remap_unforeigned!(target, references, creator_id) do
    foreign = MapSet.new(references, &{&1.table, &1.column})

    for {table, column} <- @unforeigned_columns,
        not MapSet.member?(foreign, {table, column}),
        column_exists?(target, table, column) do
      remap_column!(target, table, column, false, creator_id)
    end

    if column_exists?(target, "notification_routes", "recipient_ids") do
      query!("""
      UPDATE "#{target}"."notification_routes" AS r
      SET recipient_ids = ARRAY(
        SELECT DISTINCT m.target_id::integer
        FROM unnest(r.recipient_ids) AS recipient(id)
        JOIN pg_temp.brando_import_users AS m ON m.source_id = recipient.id AND m.matched
        ORDER BY 1
      )
      WHERE cardinality(r.recipient_ids) > 0
      """)
    end
  end

  # Revisions and pending translations keep the entry as a term; its user
  # fields are named like the foreign key columns.
  defp remap_snapshots!(target, references, mapping, creator_id) do
    keys = references |> MapSet.new(& &1.column)
    lookup = Map.new(mapping, &{&1.source_id, &1.target_id})

    @snapshot_columns
    |> Enum.filter(fn {table, column} -> column_exists?(target, table, column) end)
    |> Enum.reduce(0, fn {table, column}, undecoded ->
      %{rows: rows} = query!(~s|SELECT ctid, "#{column}" FROM "#{target}"."#{table}" WHERE "#{column}" IS NOT NULL|)
      update = ~s|UPDATE "#{target}"."#{table}" SET "#{column}" = $1 WHERE ctid = $2|
      undecoded + Enum.count(rows, &(remap_snapshot!(&1, update, keys, lookup, creator_id) == :error))
    end)
  end

  defp remap_snapshot!([ctid, binary], update, keys, lookup, creator_id) do
    with {:ok, term} <- decode(binary) do
      remapped = remap_value(term, keys, lookup, creator_id)
      if remapped != term, do: query!(update, [Brando.Utils.term_to_binary(remapped), ctid])
      :ok
    end
  end

  defp decode(binary) do
    {:ok, Brando.Utils.binary_to_term(binary)}
  rescue
    _ -> :error
  end

  # Walks maps, structs and lists. An integer under a user key becomes the
  # user here; a preloaded user (the source's) is unloaded.
  defp remap_value(map, keys, lookup, creator_id) when is_map(map) do
    map
    |> Map.to_list()
    |> Map.new(fn
      {key, value} when is_integer(value) ->
        if user_key?(key, keys), do: {key, Map.get(lookup, value, creator_id)}, else: {key, value}

      {key, %User{}} ->
        {key, %Ecto.Association.NotLoaded{__field__: key, __owner__: Map.get(map, :__struct__), __cardinality__: :one}}

      {key, value} ->
        {key, remap_value(value, keys, lookup, creator_id)}
    end)
  end

  defp remap_value(list, keys, lookup, creator_id) when is_list(list),
    do: Enum.map(list, &remap_value(&1, keys, lookup, creator_id))

  defp remap_value(other, _keys, _lookup, _creator_id), do: other

  defp user_key?(key, keys) when is_atom(key) or is_binary(key), do: MapSet.member?(keys, to_string(key))
  defp user_key?(_key, _keys), do: false

  defp remap_json!(target, references, mapping, creator_id) do
    keys = references |> MapSet.new(& &1.column)
    lookup = Map.new(mapping, &{&1.source_id, &1.target_id})

    for {table, column} <- @json_columns, column_exists?(target, table, column) do
      %{rows: rows} = query!(~s|SELECT ctid, "#{column}" FROM "#{target}"."#{table}" WHERE "#{column}" IS NOT NULL|)
      update = ~s|UPDATE "#{target}"."#{table}" SET "#{column}" = $1 WHERE ctid = $2|

      for [ctid, data] <- rows, (remapped = remap_value(data, keys, lookup, creator_id)) != data do
        query!(update, [remapped, ctid])
      end
    end

    :ok
  end

  # The dump sets each sequence to the source's position; one behind its
  # column's largest value is moved past it
  defp advance_sequences!(target) do
    sql = """
    SELECT s.relname, t.relname, a.attname
    FROM pg_class AS s
    JOIN pg_namespace AS n ON n.oid = s.relnamespace
    JOIN pg_depend AS d ON d.objid = s.oid AND d.classid = 'pg_class'::regclass AND d.deptype IN ('a', 'i')
    JOIN pg_class AS t ON t.oid = d.refobjid
    JOIN pg_attribute AS a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
    WHERE s.relkind = 'S' AND n.nspname = $1
    """

    %{rows: rows} = query!(sql, [target])

    Enum.each(rows, fn [sequence, table, column] ->
      query!("""
      SELECT setval('"#{target}"."#{sequence}"', m.max_value)
      FROM (SELECT max("#{column}")::bigint AS max_value FROM "#{target}"."#{table}") AS m
      WHERE m.max_value IS NOT NULL
        AND m.max_value > (SELECT CASE WHEN is_called THEN last_value ELSE last_value - 1 END FROM "#{target}"."#{sequence}")
      """)
    end)
  end

  ## Outside world

  defp neutralise!(target) do
    [
      update_count!(
        target,
        :webhooks_paused,
        "webhooks",
        ~s|active = false, paused_reason = 'manual', paused_at = now() AT TIME ZONE 'utc'|,
        "active"
      ),
      update_count!(
        target,
        :notification_routes_paused,
        "notification_routes",
        ~s|active = false, paused_reason = 'manual', paused_at = now() AT TIME ZONE 'utc'|,
        "active"
      ),
      update_count!(target, :markdown_sources_disabled, "content_markdown_sources", "enabled = false", "enabled"),
      update_count!(target, :index_now_disabled, "sites_indexnow", "enabled = false", "enabled"),
      update_count!(
        target,
        :provider_videos_kept_at_provider,
        "videos",
        "meta = coalesce(meta, '{}'::jsonb) || '{\"imported\": true}'::jsonb",
        "type IN (#{Enum.map_join(@provider_video_types, ", ", &"'#{&1}'")}) AND coalesce(meta->>'imported', '') <> 'true'"
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Map.put(&1, :action, :neutralised))
  end

  defp update_count!(target, key, table, set, where) do
    if table_exists?(target, table) do
      %{num_rows: count} = query!(~s|UPDATE "#{target}"."#{table}" SET #{set} WHERE #{where}|)
      %{key: key, count: count}
    end
  end

  # What the copy carries that the operator decides on
  defp to_check!(target, undecoded) do
    [
      count!(target, :scheduled_revisions, {"revisions", "scheduled"}, "scheduled = true"),
      scheduled_dates!(target),
      count!(
        target,
        :forms_with_recipients,
        {"forms", "recipients"},
        "jsonb_typeof(recipients) = 'array' AND jsonb_array_length(recipients) > 0"
      ),
      count!(target, :cdn_images, {"images", "cdn"}, "cdn = true"),
      count!(target, :cdn_files, {"files", "cdn"}, "cdn = true"),
      %{key: :undecoded_snapshots, count: undecoded}
    ]
    |> Enum.reject(&(is_nil(&1) or &1.count == 0))
    |> Enum.map(&Map.put(&1, :action, :check))
  end

  defp count!(target, key, {table, column}, where) do
    if column_exists?(target, table, column) do
      %{rows: [[count]]} = query!(~s|SELECT count(*) FROM "#{target}"."#{table}" WHERE #{where}|)
      %{key: key, count: count}
    end
  end

  # Dates are naive UTC, as Ecto writes them
  defp scheduled_dates!(target) do
    sql = """
    SELECT table_name, array_agg(column_name::text ORDER BY column_name) FROM information_schema.columns
    WHERE table_schema = $1 AND column_name IN ('publish_at', 'unpublish_at')
    GROUP BY table_name
    """

    %{rows: rows} = query!(sql, [target])

    count =
      Enum.reduce(rows, 0, fn [table, columns], acc ->
        future = Enum.map_join(columns, " OR ", &~s|"#{&1}" > (now() AT TIME ZONE 'utc')|)
        %{rows: [[count]]} = query!(~s|SELECT count(*) FROM "#{target}"."#{table}" WHERE #{future}|)
        acc + count
      end)

    %{key: :scheduled_dates, count: count}
  end

  ## Helpers

  defp schema_exists?(schema) do
    match?({:ok, %{rows: [[true]]}}, query("SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = $1)", [schema]))
  end

  defp table_exists?(schema, table) do
    match?(
      {:ok, %{rows: [[true]]}},
      query("SELECT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = $1 AND tablename = $2)", [schema, table])
    )
  end

  defp column_exists?(schema, table, column) do
    sql =
      "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2 AND column_name = $3)"

    match?({:ok, %{rows: [[true]]}}, query(sql, [schema, table, column]))
  end

  defp transaction(fun) do
    Brando.Repo.repo().transaction(fun, timeout: :infinity)
  rescue
    exception -> {:error, {:import_failed, Exception.message(exception)}}
  end

  defp query(sql, params \\ []), do: SQL.query(Brando.Repo.repo(), sql, params, timeout: :infinity)
  defp query!(sql, params \\ []), do: SQL.query!(Brando.Repo.repo(), sql, params, timeout: :infinity)
end
