defmodule Brando.MigrationTemplates do
  @moduledoc false
  # Runs Brando's upgrade migration templates (`priv/templates/brando.upgrade/
  # migrations`) inside a test's sandbox transaction, and inspects what they
  # did in `public` and in environment schemas. Postgres DDL is transactional,
  # so the sandbox undoes everything, schemas included.
  #
  # Templates that loop over "every environment" find their schemas by name
  # (`tenant_<site>_<environment>`), so an environment here is just a schema
  # with that name and copies of the `public` tables the template touches.

  alias BrandoIntegration.Repo

  @templates Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations")

  @doc "The path of the template named `file`"
  def path(file), do: Path.join(@templates, file)

  @doc "The path of `file` among the shipped versions of the template `name`"
  def history(name, file), do: Path.join([@templates, "..", "history", name, file])

  @doc "Every `brando_2xx` template, in the order `mix brando.gen.migrations` copies them"
  def brando_2xx do
    @templates
    |> Path.join("brando_2??_*.exs")
    |> Path.wildcard()
    |> Enum.map(&Path.basename/1)
    |> Enum.sort_by(&number/1)
  end

  @doc "The number in a template's name: 212 for `brando_212_add_search_documents.exs`"
  def number(file) do
    [_, number] = Regex.run(~r/^brando_(\d+)_/, file)
    String.to_integer(number)
  end

  @doc """
  Runs a template's `up/0` as a migration with a fresh version, and returns
  the version for `down/2`.
  """
  def up(file) do
    version = System.unique_integer([:positive])
    with_module(file, &(:ok = Ecto.Migrator.up(Repo, version, &1, log: false, migration_lock: false)))
    version
  end

  @doc "Runs a template's `down/0` for the version `up/1` returned"
  def down(file, version) do
    with_module(file, &(:ok = Ecto.Migrator.down(Repo, version, &1, log: false, migration_lock: false)))
  end

  defp with_module(file, fun) do
    [{module, _bytecode}] = Code.compile_file(path(file))

    try do
      fun.(module)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  @doc """
  Creates an environment schema holding copies of the `public` tables in
  `tables`, as provisioning would (`Brando.Environments.StructureCloner`):
  structure only, with defaults, constraints and indexes.
  """
  def create_environment(prefix, tables \\ []) do
    query!(~s(CREATE SCHEMA "#{prefix}"))
    copy_tables("public", prefix, tables, false)
    prefix
  end

  @doc "Copies one table's structure, as `copy_tables/4` does"
  def copy_table(source, target, table), do: copy_tables(source, target, [table], false)

  @doc """
  Copies tables from `source` into the existing `target` schema the way
  pg_dump and the environment cloners do, inside the sandbox: columns,
  defaults and checks; sequences of their own; primary keys, unique
  constraints and indexes under their own names; foreign keys, those between
  copied tables pointing into `target`; and, with `rows?`, the rows.
  """
  def copy_tables(source, target, tables, rows?) do
    # Definitions name every schema when the search path is empty
    [[search_path]] = rows("SHOW search_path")
    query!("SET search_path TO ''")

    try do
      Enum.each(tables, &create_table(source, target, &1))
      if rows?, do: Enum.each(tables, &copy_rows(source, target, &1))

      definitions = constraint_definitions(source, tables)

      for {table, name, "p", definition} <- definitions, do: add_constraint(target, table, name, definition)
      for {table, name, "u", definition} <- definitions, do: add_constraint(target, table, name, definition)
      Enum.each(tables, &copy_indexes(source, target, &1))

      for {table, name, "f", definition} <- definitions do
        definition =
          Regex.replace(
            ~r/REFERENCES (?:"#{Regex.escape(source)}"|#{Regex.escape(source)})\.("?)(\w+)\1\(/,
            definition,
            fn
              match, _quote, referenced ->
                if referenced in tables, do: ~s{REFERENCES "#{target}"."#{referenced}"(}, else: match
            end
          )

        add_constraint(target, table, name, definition)
      end
    after
      query!("SELECT set_config('search_path', $1, false)", [search_path])
    end

    :ok
  end

  defp create_table(source, target, table) do
    query!(
      ~s{CREATE TABLE "#{target}"."#{table}" (LIKE "#{source}"."#{table}" INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING IDENTITY INCLUDING GENERATED)}
    )

    # A serial column gets a sequence of its own in the copy
    for [column, default] <-
          rows(
            "SELECT column_name, column_default FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2",
            [target, table]
          ),
        [_, sequence] <- [Regex.run(~r/^nextval\('(?:[^']*\.)?"?([\w-]+)"?'::regclass\)$/, default || "")] do
      query!(~s{CREATE SEQUENCE IF NOT EXISTS "#{target}"."#{sequence}"})

      query!(
        ~s{ALTER TABLE "#{target}"."#{table}" ALTER COLUMN "#{column}" SET DEFAULT nextval('"#{target}"."#{sequence}"'::regclass)}
      )
    end
  end

  defp copy_rows(source, target, table) do
    query!(~s{INSERT INTO "#{target}"."#{table}" SELECT * FROM "#{source}"."#{table}"})

    for [column, default] <-
          rows(
            "SELECT column_name, column_default FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2",
            [target, table]
          ),
        default && String.starts_with?(default, "nextval(") do
      query!(
        ~s{SELECT setval(pg_get_serial_sequence('"#{target}"."#{table}"', $1), coalesce((SELECT max("#{column}") FROM "#{target}"."#{table}"), 0) + 1, false)},
        [column]
      )
    end
  end

  defp constraint_definitions(source, tables) do
    """
    SELECT rel.relname, c.conname, c.contype::text, pg_get_constraintdef(c.oid)
    FROM pg_constraint c
    JOIN pg_class rel ON rel.oid = c.conrelid
    JOIN pg_namespace ns ON ns.oid = rel.relnamespace
    WHERE ns.nspname = $1 AND rel.relname = ANY($2) AND c.contype IN ('p', 'u', 'f')
    """
    |> rows([source, tables])
    |> Enum.map(&List.to_tuple/1)
  end

  defp add_constraint(target, table, name, definition),
    do: query!(~s{ALTER TABLE "#{target}"."#{table}" ADD CONSTRAINT "#{name}" #{definition}})

  # Indexes that do not back a constraint, under their own names
  defp copy_indexes(source, target, table) do
    """
    SELECT pg_get_indexdef(i.indexrelid)
    FROM pg_index i
    JOIN pg_class rel ON rel.oid = i.indrelid
    JOIN pg_namespace ns ON ns.oid = rel.relnamespace
    WHERE ns.nspname = $1 AND rel.relname = $2
      AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
    """
    |> rows([source, table])
    |> Enum.each(fn [definition] ->
      definition
      |> String.replace(~s( ON "#{source}".), ~s( ON "#{target}".))
      |> String.replace(" ON #{source}.", ~s( ON "#{target}".))
      |> query!()
    end)
  end

  def query!(sql, params \\ []), do: Repo.query!(sql, params)

  def rows(sql, params \\ []), do: query!(sql, params).rows

  def table?(schema, table), do: rows("SELECT to_regclass($1)::text", [~s("#{schema}"."#{table}")]) != [[nil]]

  def tables(schema) do
    "SELECT tablename FROM pg_tables WHERE schemaname = $1"
    |> rows([schema])
    |> List.flatten()
    |> Enum.sort()
  end

  def columns(schema, table) do
    "SELECT column_name FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2"
    |> rows([schema, table])
    |> List.flatten()
    |> Enum.sort()
  end

  @doc "`[{column, data_type, nullable?, default}]`, comparable across schemas"
  def column_definitions(schema, table) do
    """
    SELECT column_name, data_type, is_nullable = 'YES', column_default
    FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2
    """
    |> rows([schema, table])
    |> Enum.map(fn [name, type, nullable, default] -> {name, type, nullable, unqualify(default, schema)} end)
    |> Enum.sort()
  end

  @doc "Index definitions with the schema taken out, comparable across schemas"
  def indexes(schema, table) do
    "SELECT indexdef FROM pg_indexes WHERE schemaname = $1 AND tablename = $2"
    |> rows([schema, table])
    |> List.flatten()
    |> Enum.map(&unqualify(&1, schema))
    |> Enum.sort()
  end

  @doc "Where each foreign key of `table` in `schema` points: `[{column, schema, table}]`"
  def references(schema, table) do
    """
    SELECT a.attname, ref_ns.nspname, ref.relname
    FROM pg_constraint c
    JOIN pg_class rel ON rel.oid = c.conrelid
    JOIN pg_namespace ns ON ns.oid = rel.relnamespace
    JOIN pg_class ref ON ref.oid = c.confrelid
    JOIN pg_namespace ref_ns ON ref_ns.oid = ref.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE c.contype = 'f' AND ns.nspname = $1 AND rel.relname = $2
    """
    |> rows([schema, table])
    |> Enum.map(&List.to_tuple/1)
    |> Enum.sort()
  end

  # A database from before the brando_2xx migrations

  @doc "What the 2xx migrations add in every environment: tables"
  def environment_tables,
    do: ~w(sites_not_found_hits entry_notes note_mentions webhooks webhook_deliveries sites_indexnow search_documents
         listing_views listing_view_defaults notification_routes notification_deliveries)

  @doc "What the 2xx migrations add in every environment: columns by table"
  def environment_columns do
    %{
      "pages" => ~w(meta_canonical_url content_modified_at meta_nosnippet meta_max_snippet unpublish_at),
      "pages_fragments" => ~w(unpublish_at),
      "sites_seos" => ~w(crawler_policy),
      "content_modules" => ~w(markdown_code write_with_ai),
      "activity_events" => ~w(proposal_id approver_id)
    }
  end

  @doc "What the 2xx migrations add in `public` only: tables"
  def public_tables do
    ~w(users_security users_recovery_codes users_security_events users_security_policy users_passkeys
       mcp_settings mcp_grants mcp_tokens mcp_authorization_codes)
  end

  @doc "What the 2xx migrations add in `public` only: columns by table"
  def public_columns do
    %{
      "users" => ~w(job_title same_as),
      "users_tokens" => ~w(ip user_agent last_used_at confirmed_at),
      "content_proposals" => ~w(origin client)
    }
  end

  @doc "Rolls `public` back to before the 2xx migrations"
  def roll_back_2xx do
    query!("DROP TABLE #{Enum.join(environment_tables() ++ public_tables(), ", ")}")

    for {table, names} <- Map.merge(environment_columns(), public_columns()) do
      query!(~s(ALTER TABLE "#{table}" ) <> Enum.map_join(names, ", ", &"DROP COLUMN #{&1}"))
    end
  end

  @doc """
  Copies the 2xx templates into `directory` under the versions
  `mix brando.gen.migrations` gives them, and returns `{version, file}`
  """
  def copy_2xx(directory) do
    for {_format, "../brando.upgrade/migrations/" <> file, target} <- Mix.Brando.Install.Templates.manifest(),
        file =~ ~r/^brando_2\d\d_/ do
      File.cp!(path(file), Path.join(directory, Path.basename(target)))
      {target |> Path.basename() |> Integer.parse() |> elem(0), file}
    end
  end

  @doc """
  Runs a migrations directory as `mix brando.migrate` does, then unloads the
  migration modules so the next run compiles them afresh
  """
  def migrate(directory, direction) do
    versions =
      Ecto.Migrator.run(Repo, [directory], direction, all: true, log: false, migration_lock: false)

    for file <- Path.wildcard(Path.join(directory, "*.exs")),
        [_, module] <- [Regex.run(~r/defmodule (\S+) do/, File.read!(file))] do
      module = Module.concat([module])
      :code.purge(module)
      :code.delete(module)
    end

    versions
  end

  @gallery_loop """
  {% assign images = refs.slider.gallery.gallery_objects %}
  {% for image in images %}{% picture image %}{% endfor %}
  """

  @doc """
  An environment as provisioning makes it (every non-shared table of
  `public`), with a page and a module whose gallery loop brando_200 fixes.
  Returns their ids.
  """
  def provision(prefix) do
    {:ok, tables} = Brando.Environments.StructureCloner.Postgres.tenant_tables("public")
    create_environment(prefix, tables)

    [[page_id]] =
      rows("""
      INSERT INTO "#{prefix}".pages (uri, language, title, template, edited_at, inserted_at, updated_at)
      VALUES ('about', 'en', 'About #{prefix}', 'default.html', '2026-01-01 10:00:00', '2025-01-01 10:00:00', '2026-05-01 10:00:00')
      RETURNING id
      """)

    [[module_id]] =
      rows(
        """
        INSERT INTO "#{prefix}".content_modules (uid, class, code, inserted_at, updated_at)
        VALUES ($1, 'slider', $2, NOW(), NOW()) RETURNING id
        """,
        [Brando.Utils.generate_uid(), @gallery_loop]
      )

    %{page: page_id, module: module_id}
  end

  @doc "Copies every table of `source`, with its rows, into a new `target` schema"
  def copy_schema(source, target) do
    query!(~s(CREATE SCHEMA "#{target}"))
    copy_tables(source, target, tables(source), true)
  end

  @doc "`{columns, indexes, references}` of each table"
  def table_set(schema, tables),
    do: Map.new(tables, &{&1, {column_definitions(schema, &1), indexes(schema, &1), references(schema, &1)}})

  @doc "The definitions of the named columns, by table"
  def column_set(schema, columns) do
    for {table, names} <- columns,
        do: {table, schema |> column_definitions(table) |> Enum.filter(&(elem(&1, 0) in names))},
        into: %{}
  end

  defp unqualify(nil, _schema), do: nil

  defp unqualify(sql, schema) do
    sql
    |> String.replace(~s("#{schema}".), "")
    |> String.replace("#{schema}.", "")
  end

  defmodule InProcessMigrator do
    @moduledoc false
    # `Ecto.Migrator.up/4` runs a migration in a task, on a connection of its
    # own. Inside the sandbox, while `Brando.Environments` holds the one
    # connection for a site's lock, it never gets one; this runs the
    # migration in the calling process instead.

    def up(repo, version, module, opts) do
      config = repo.config()

      {:ok, :ok} =
        repo.transaction(fn ->
          Ecto.Migration.Runner.run(repo, config, version, module, :forward, :up, :up, opts)
          Ecto.Migration.SchemaMigration.up(repo, config, version, opts)
          :ok
        end)

      :ok
    end
  end
end
