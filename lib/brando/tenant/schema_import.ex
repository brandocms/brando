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
  whose email matches a user here, ignoring case, becomes that user (the
  first by id, when several match the same one), and every other one becomes
  the creator.

  The references are found from the target's foreign keys to `public.users`,
  plus the user ids Brando stores without one:

    * `content_markdown_events.actor_id`, remapped like a foreign key;
    * `notification_routes.recipient_ids`, where a recipient with no match
      here is dropped rather than replaced by the creator;
    * the entry snapshots in `revisions.encoded_entry` and
      `translation_pending_versions.payload`, so that restoring a revision
      does not write a source user's id. In each struct of a snapshot the
      fields remapped are the columns of that struct's table with a foreign
      key to `users`, so an application's `author_id` that points at its own
      authors table is left alone. A snapshot that cannot be decoded here is
      left as it is and counted in the report;
    * the block rows kept in `content_block_archive.data`, by the same rule
      per table;
    * the mention tokens (`<@12>`) in `entry_notes.body`: a mention of a
      matched user names that user here, and one of a user with no match
      becomes plain text, `@` and the source user's name (or email), so that
      it names no one here. A token of an id the source's `users` table does
      not have becomes `@?`, as `Brando.Notes.plain_text/2` shows an unknown
      mention.

  A row whose user column is part of a unique index (listing defaults, note
  mentions, notification deliveries, personal listing views) belongs to that
  user: for a user with no match here it is deleted, since giving every such
  row to the creator would collide. A shared listing view is everyone's, so
  one made by a user with no match goes to the creator (renamed `name (id)`,
  or `name (id, 2)` and so on when that is taken too, when the creator
  already has a view of that name), and the defaults that
  point at it stay. Ids are moved through negative values, which no user has,
  so users whose ids are each other's ids here never collide on the way.

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

  `Brando.Tenant.Migration.import_schema/3` keeps the new site suspended
  until all of this has committed, so no worker or request acts on the copy
  before.

  Deploy targets live in the shared `sites` registry and are not copied: the
  new site delivers dynamically until an operator configures one. Oban jobs
  are shared and not copied either, so a scheduled revision's job stays with
  the source (the report counts them), while `publish_at` and `unpublish_at`
  dates are carried out by `Brando.Worker.ScheduledPublishingSweep`.

  ## Structure, languages and sequences

  The source's tenant tables must match this installation's (`compare/1`). A
  table the source does not have is not a difference: an application's
  content type the imported site never used. Nothing is copied into it, and
  the report names it; a table Brando derives from content (`derived_tables/0`)
  is named apart, with the action that rebuilds it. Content in a language this installation does not
  configure cannot be loaded here (`content_languages/1`).

  The dump's own sequence positions (`setval`) are dropped, since an older
  installation may name a sequence differently. Each sequence here is set
  from the source's sequence of the same table and column, or past the
  column's largest value, whichever is further.
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
  @mention_token ~r/<@(\d+)>/
  # Tables Brando derives from content, with the Configuration → Utilities
  # action that rebuilds each in the current environment
  @derived_tables %{"search_documents" => "Rebuild search index", "content_identifiers" => "Sync identifiers"}
  @batch_size 500

  @typedoc "One source user and the user here it becomes."
  @type mapping_entry :: %{
          required(:source_id) => integer(),
          required(:source_email) => String.t() | nil,
          optional(:source_name) => String.t() | nil,
          optional(:duplicate_of) => integer(),
          required(:target_id) => integer(),
          required(:target_email) => String.t(),
          required(:matched) => boolean()
        }

  @typedoc """
  One line of the closing report: what was found, how many, what was done,
  and for some the names of what was found (`:tables_not_in_source`,
  `:derived_tables_not_in_source`).
  """
  @type report_item :: %{
          required(:key) => atom(),
          required(:count) => non_neg_integer(),
          required(:action) => :neutralised | :check,
          optional(:names) => [String.t()]
        }

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

  Returns `{:error, {:source_structure_differs, differences}}` when the source
  has a table this installation does not, a table both have lacks a column on
  either side, or a column's type differs. Each difference is
  `{:extra_table, table}` (in the source, not here), `{:missing_column,
  table, column}`, `{:extra_column, table, column}` or `{:type_differs,
  table, column, source_type, type_here}`. A table here that the source does
  not have is not a difference: `copy/4` copies nothing into it and names it
  in the report.
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
      {:extra_table, table} -> "  table #{table}: only in the source"
      {:missing_column, table, column} -> "  column #{table}.#{column}: missing in the source"
      {:extra_column, table, column} -> "  column #{table}.#{column}: only in the source"
      {:type_differs, table, column, there, here} -> "  column #{table}.#{column}: #{there} in the source, #{here} here"
    end)
  end

  @doc """
  Maps every user in the source's `users` table to a user here: the one whose
  email matches, ignoring case, or `creator`. Creates no user. When several
  source users match the same user here, the first by id does, and each
  later one becomes `creator`, unmatched, with `:duplicate_of` the first
  one's source id.
  """
  @spec user_mapping(String.t(), User.t()) :: {:ok, [mapping_entry()]} | {:error, term()}
  def user_mapping(source, %User{} = creator) do
    name = if column_exists?(source, "users", "name"), do: "name", else: "NULL::text"

    with :ok <- validate_source(source),
         {:ok, %{rows: source_users}} <- query(~s|SELECT id, email, #{name} FROM "#{source}"."users" ORDER BY id|) do
      local =
        from(u in User,
          where: is_nil(u.deleted_at),
          order_by: [asc: u.id],
          select: {fragment("lower(?)", u.email), u.id, u.email}
        )
        |> Brando.Repo.all(prefix: "public")
        |> Enum.reduce(%{}, fn {lower, id, email}, acc -> Map.put_new(acc, lower, {id, email}) end)

      {:ok,
       source_users
       |> Enum.map(&map_user(&1, local, creator))
       |> Enum.map_reduce(%{}, &first_match(&1, &2, creator))
       |> elem(0)}
    end
  end

  # One user here is matched by one source user at most, the first by id: two
  # would collide in a table with a unique index on the user column. A later
  # one becomes the creator, as a user with no match does.
  defp first_match(%{matched: true, target_id: target_id} = entry, matched, creator) do
    case Map.fetch(matched, target_id) do
      {:ok, first} ->
        {%{entry | target_id: creator.id, target_email: creator.email, matched: false} |> Map.put(:duplicate_of, first),
         matched}

      :error ->
        {entry, Map.put(matched, target_id, entry.source_id)}
    end
  end

  defp first_match(entry, matched, _creator), do: {entry, matched}

  defp map_user([id, email, name], local, creator) do
    source = %{source_id: id, source_email: email, source_name: name}

    case is_binary(email) && Map.get(local, String.downcase(email)) do
      {target_id, target_email} -> Map.merge(source, %{target_id: target_id, target_email: target_email, matched: true})
      _ -> Map.merge(source, %{target_id: creator.id, target_email: creator.email, matched: false})
    end
  end

  @doc """
  The languages of the source's content: every value of a `language` column
  in its tenant tables, with the tables that hold it, as `[{language,
  [table]}]`. Only the tables of Blueprints (Brando's and the
  application's) whose `language` is the language enum are read: they are
  the rows that cannot load a language this installation does not configure.
  A `language` that is a plain string, such as an activity event's, loads
  whatever its value. Only reads the source.
  """
  @spec content_languages(String.t()) :: {:ok, [{String.t(), [String.t()]}]} | {:error, term()}
  def content_languages(source) do
    sql = """
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = $1 AND column_name = 'language' AND data_type IN ('text', 'character varying')
    ORDER BY table_name
    """

    with :ok <- validate_source(source),
         {:ok, %{rows: rows}} <- query(sql, [source]) do
      enum_tables = language_enum_tables()

      rows
      |> Enum.map(&List.first/1)
      |> Enum.filter(&(&1 in enum_tables and not SharedTables.member?(&1)))
      |> Enum.reduce_while({:ok, []}, &collect_languages(source, &1, &2))
      |> group_languages()
    end
  end

  defp language_enum_tables do
    (Brando.Blueprint.brando_blueprints() ++ Brando.Blueprint.list_blueprints())
    |> Enum.uniq()
    |> Enum.filter(&(function_exported?(&1, :__schema__, 2) and language_enum?(&1.__schema__(:type, :language))))
    |> Enum.map(& &1.__schema__(:source))
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp language_enum?({:parameterized, {Ecto.Enum, _params}}), do: true
  defp language_enum?(_type), do: false

  defp collect_languages(source, table, {:ok, acc}) do
    case query(~s|SELECT DISTINCT "language" FROM "#{source}"."#{table}" WHERE "language" IS NOT NULL|) do
      {:ok, %{rows: languages}} -> {:cont, {:ok, acc ++ Enum.map(languages, &{List.first(&1), table})}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp group_languages({:ok, pairs}), do: {:ok, pairs |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Enum.sort()}
  defp group_languages(error), do: error

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
         {:ok, not_in_source} <- tables_not_in_source(target, tables),
         {:ok, references} <- user_references(target),
         :ok <- drop_constraints(target, references),
         {:ok, dump} <- SchemaCloner.dump_schema(source, dump_args(source, tables)),
         {:ok, rewritten} <- SchemaCloner.rewrite_schema(dump, source, target),
         :ok <- SchemaCloner.restore_dump(without_sequence_positions(rewritten)) do
      transaction(fn ->
        remap_references!(target, references, mapping, creator_id)
        remap_unforeigned!(target, references, creator_id)
        undecoded = remap_snapshots!(target, references, mapping, creator_id)
        remap_json!(target, references, mapping, creator_id)
        remap_mentions!(target, mapping)
        add_constraints!(target, references)
        advance_sequences!(source, target)
        neutralised = neutralise!(target)
        neutralised ++ to_check!(target, undecoded, not_in_source)
      end)
    end
  end

  @doc """
  The tables Brando derives from content, each with the Configuration →
  Utilities action that rebuilds it in an environment. The report names
  those the source does not have as `:derived_tables_not_in_source`.
  """
  @spec derived_tables() :: %{String.t() => String.t()}
  def derived_tables, do: @derived_tables

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
        {nil, _} -> []
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

  defp tables_not_in_source(target, copied) do
    with {:ok, %{rows: rows}} <-
           query("SELECT tablename FROM pg_tables WHERE schemaname = $1 ORDER BY tablename", [target]) do
      {:ok, rows |> Enum.map(&List.first/1) |> Enum.reject(&(SharedTables.member?(&1) or &1 in copied))}
    end
  end

  # The source's names for its sequences may not be the names here; they are
  # set by table and column in `advance_sequences!/2`
  defp without_sequence_positions(dump) do
    dump
    |> String.split("\n")
    |> Enum.map_reduce(:sql, fn
      "\\." = line, :copy_data -> {[line], :sql}
      line, :copy_data -> {[line], :copy_data}
      "SELECT pg_catalog.setval(" <> _, :sql -> {[], :sql}
      line, :sql -> {[line], if(copy_from_stdin?(line), do: :copy_data, else: :sql)}
    end)
    |> elem(0)
    |> Enum.concat()
    |> Enum.join("\n")
  end

  defp copy_from_stdin?(line), do: String.starts_with?(line, "COPY ") and String.ends_with?(line, " FROM stdin;")

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

  # A personal row of a user with no match here is deleted, except a shared
  # listing view, which goes to the creator; every other reference becomes its
  # match or the creator, an id not in the source's users table included.
  # Personal rows move through negative ids, which no user has: a row moved
  # straight to its new id could meet the row of a user whose source id that
  # is, and fail its unique index.
  defp remap_column!(target, table, column, true, creator_id) do
    qualified = ~s|"#{target}"."#{table}"|
    shared_views? = {table, column} == {"listing_views", "creator_id"} and column_exists?(target, table, "shared")

    query!("""
    DELETE FROM #{qualified} AS t
    WHERE t."#{column}" IS NOT NULL #{if shared_views?, do: "AND NOT t.shared"}
      AND NOT EXISTS (SELECT 1 FROM pg_temp.brando_import_users AS m WHERE m.source_id = t."#{column}" AND m.matched)
    """)

    if shared_views?, do: rename_colliding_views!(qualified, creator_id)

    query!(
      """
      UPDATE #{qualified} AS t
      SET "#{column}" = -coalesce((SELECT m.target_id FROM pg_temp.brando_import_users AS m WHERE m.source_id = t."#{column}"), $1)
      WHERE t."#{column}" IS NOT NULL
      """,
      [creator_id]
    )

    query!(~s|UPDATE #{qualified} SET "#{column}" = -"#{column}" WHERE "#{column}" < 0|)
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

  # A view's name is unique per owner and listing: a view that would take the
  # name of another of its new owner's views gets its id after the name
  # (`team (4)`, then `team (4, 2)`, …), the first such name that neither its
  # current owner nor its new owner has. A matched user's views keep theirs.
  defp rename_colliding_views!(qualified, creator_id) do
    %{rows: rows} =
      query!(
        """
        SELECT r.id, r.name, r.creator_id, r.owner, r.schema, r.listing
        FROM (
          SELECT w.id, w.name, w.creator_id, w.schema, w.listing, coalesce(m.target_id, $1) AS owner,
            row_number() OVER (
              PARTITION BY coalesce(m.target_id, $1), w.schema, w.listing, w.name
              ORDER BY coalesce(m.matched, false) DESC, w.id
            ) AS n
          FROM #{qualified} AS w
          LEFT JOIN pg_temp.brando_import_users AS m ON m.source_id = w.creator_id
        ) AS r
        WHERE r.n > 1
        ORDER BY r.id
        """,
        [creator_id]
      )

    Enum.each(rows, fn [id, name, current, owner, schema, listing] ->
      free =
        1
        |> Stream.iterate(&(&1 + 1))
        |> Stream.map(fn
          1 -> "#{name} (#{id})"
          n -> "#{name} (#{id}, #{n})"
        end)
        |> Enum.find(&(not view_name_taken?(qualified, &1, {current, owner, schema, listing}, creator_id)))

      query!("UPDATE #{qualified} SET name = $1 WHERE id = $2", [free, id])
    end)
  end

  defp view_name_taken?(qualified, name, {current, owner, schema, listing}, creator_id) do
    %{rows: [[taken]]} =
      query!(
        """
        SELECT EXISTS (
          SELECT 1 FROM #{qualified} AS w
          LEFT JOIN pg_temp.brando_import_users AS m ON m.source_id = w.creator_id
          WHERE w.schema = $1 AND w.listing = $2 AND w.name = $3
            AND (w.creator_id = $4 OR coalesce(m.target_id, $5) = $6)
        )
        """,
        [schema, listing, name, current, creator_id, owner]
      )

    taken
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

  # Revisions and pending translations keep the entry as a term. In each
  # struct, the user fields are its table's columns with a foreign key to
  # users.
  defp remap_snapshots!(target, references, mapping, creator_id) do
    keys = keys_by_table(references)
    lookup = Map.new(mapping, &{&1.source_id, &1.target_id})

    @snapshot_columns
    |> Enum.filter(fn {table, column} -> column_exists?(target, table, column) end)
    |> Enum.reduce(0, fn {table, column}, undecoded ->
      update = ~s|UPDATE "#{target}"."#{table}" SET "#{column}" = $1 WHERE ctid = $2|

      reduce_rows!(
        ~s|SELECT ctid, "#{column}" FROM "#{target}"."#{table}" WHERE "#{column}" IS NOT NULL|,
        undecoded,
        &count_undecoded!(&1, &2, update, keys, lookup, creator_id)
      )
    end)
  end

  defp count_undecoded!(row, undecoded, update, keys, lookup, creator_id) do
    if remap_snapshot!(row, update, keys, lookup, creator_id) == :error, do: undecoded + 1, else: undecoded
  end

  defp remap_snapshot!([ctid, binary], update, keys, lookup, creator_id) do
    with {:ok, term} <- decode(binary) do
      remapped = remap_value(term, MapSet.new(), keys, lookup, creator_id)
      if remapped != term, do: query!(update, [Brando.Utils.term_to_binary(remapped), ctid])
      :ok
    end
  end

  defp decode(binary) do
    {:ok, Brando.Utils.binary_to_term(binary)}
  rescue
    _ -> :error
  end

  defp keys_by_table(references) do
    references
    |> Enum.group_by(& &1.table, & &1.column)
    |> Map.new(fn {table, columns} -> {table, MapSet.new(columns)} end)
  end

  # Walks maps, structs and lists. An integer under one of `user_keys`
  # becomes the user here; a preloaded user (the source's) is unloaded. An
  # Ecto struct's user keys are its own table's, and a plain map in it has
  # none.
  defp remap_value(%{__struct__: module} = struct, _user_keys, keys, lookup, creator_id) do
    remap_fields(struct, struct_keys(module, keys), keys, lookup, creator_id)
  end

  defp remap_value(map, user_keys, keys, lookup, creator_id) when is_map(map),
    do: remap_fields(map, user_keys, keys, lookup, creator_id)

  defp remap_value(list, user_keys, keys, lookup, creator_id) when is_list(list),
    do: Enum.map(list, &remap_value(&1, user_keys, keys, lookup, creator_id))

  defp remap_value(other, _user_keys, _keys, _lookup, _creator_id), do: other

  defp remap_fields(map, user_keys, keys, lookup, creator_id) do
    map
    |> Map.to_list()
    |> Map.new(fn
      {key, value} when is_integer(value) ->
        if user_key?(key, user_keys), do: {key, Map.get(lookup, value, creator_id)}, else: {key, value}

      {key, %User{}} ->
        {key, %Ecto.Association.NotLoaded{__field__: key, __owner__: Map.get(map, :__struct__), __cardinality__: :one}}

      {key, value} ->
        {key, remap_value(value, MapSet.new(), keys, lookup, creator_id)}
    end)
  end

  defp struct_keys(module, keys) do
    source = Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and module.__schema__(:source)
    if is_binary(source), do: Map.get(keys, source, MapSet.new()), else: MapSet.new()
  end

  defp user_key?(key, keys) when is_atom(key) or is_binary(key), do: MapSet.member?(keys, to_string(key))
  defp user_key?(_key, _keys), do: false

  # The archive keeps each table's rows under the table's name
  defp remap_json!(target, references, mapping, creator_id) do
    keys = keys_by_table(references)
    lookup = Map.new(mapping, &{&1.source_id, &1.target_id})

    for {table, column} <- @json_columns, column_exists?(target, table, column) do
      update = ~s|UPDATE "#{target}"."#{table}" SET "#{column}" = $1 WHERE ctid = $2|

      reduce_rows!(
        ~s|SELECT ctid, "#{column}" FROM "#{target}"."#{table}" WHERE "#{column}" IS NOT NULL|,
        :ok,
        fn row, :ok -> remap_json_row!(row, update, keys, lookup, creator_id) end
      )
    end

    :ok
  end

  defp remap_json_row!([ctid, data], update, keys, lookup, creator_id) do
    remapped = remap_tables(data, keys, lookup, creator_id)
    if remapped != data, do: query!(update, [remapped, ctid])
    :ok
  end

  defp remap_tables(data, keys, lookup, creator_id) when is_map(data) do
    Map.new(data, fn {table, rows} ->
      {table, remap_value(rows, Map.get(keys, table, MapSet.new()), keys, lookup, creator_id)}
    end)
  end

  defp remap_tables(data, _keys, _lookup, _creator_id), do: data

  defp remap_mentions!(target, mapping) do
    if column_exists?(target, "entry_notes", "body") do
      by_id = Map.new(mapping, &{&1.source_id, &1})
      update = ~s|UPDATE "#{target}"."entry_notes" SET body = $1 WHERE ctid = $2|

      reduce_rows!(~s|SELECT ctid, body FROM "#{target}"."entry_notes" WHERE body ~ '<@[0-9]+>'|, :ok, fn
        [ctid, body], :ok ->
          query!(update, [replace_mentions(body, by_id), ctid])
          :ok
      end)
    end
  end

  # A matched user's token names the user here; an unmatched one's becomes
  # plain text, and one of an id the source's users do not have `@?`
  defp replace_mentions(body, by_id) do
    Regex.replace(@mention_token, body, fn _token, id ->
      case Map.get(by_id, String.to_integer(id)) do
        %{matched: true, target_id: target_id} -> "<@#{target_id}>"
        %{} = entry -> "@" <> (Map.get(entry, :source_name) || entry.source_email || "?")
        nil -> "@?"
      end
    end)
  end

  # Through a cursor, `@batch_size` rows at a time. It reads the rows as they
  # were when it was opened, so a row the callback updates is not read again.
  defp reduce_rows!(sql, acc, fun) do
    query!("DECLARE brando_import_rows NO SCROLL CURSOR FOR #{sql}")
    result = fetch_rows!(acc, fun)
    query!("CLOSE brando_import_rows")
    result
  end

  defp fetch_rows!(acc, fun) do
    case query!("FETCH #{@batch_size} FROM brando_import_rows") do
      %{rows: []} -> acc
      %{rows: rows} -> fetch_rows!(Enum.reduce(rows, acc, fun), fun)
    end
  end

  # Each sequence here continues after the source's sequence of the same
  # table and column (read, not changed) and after the column's largest value
  defp advance_sequences!(source, target) do
    positions =
      source
      |> owned_sequences!()
      |> Map.new(fn [sequence, table, column] ->
        %{rows: [[position]]} =
          query!(~s|SELECT CASE WHEN is_called THEN last_value ELSE last_value - 1 END FROM "#{source}"."#{sequence}"|)

        {{table, column}, position}
      end)

    target
    |> owned_sequences!()
    |> Enum.each(fn [sequence, table, column] ->
      query!(
        """
        SELECT setval('"#{target}"."#{sequence}"', m.position)
        FROM (SELECT greatest(max("#{column}")::bigint, $1::bigint) AS position FROM "#{target}"."#{table}") AS m
        WHERE m.position > 0
        """,
        [Map.get(positions, {table, column})]
      )
    end)
  end

  defp owned_sequences!(schema) do
    sql = """
    SELECT s.relname, t.relname, a.attname
    FROM pg_class AS s
    JOIN pg_namespace AS n ON n.oid = s.relnamespace
    JOIN pg_depend AS d ON d.objid = s.oid AND d.classid = 'pg_class'::regclass AND d.deptype IN ('a', 'i')
    JOIN pg_class AS t ON t.oid = d.refobjid
    JOIN pg_attribute AS a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
    WHERE s.relkind = 'S' AND n.nspname = $1
    """

    query!(sql, [schema]).rows
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
  defp to_check!(target, undecoded, not_in_source) do
    {derived, left_empty} = Enum.split_with(not_in_source, &Map.has_key?(@derived_tables, &1))

    [
      %{key: :tables_not_in_source, count: length(left_empty), names: left_empty},
      %{key: :derived_tables_not_in_source, count: length(derived), names: derived},
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
