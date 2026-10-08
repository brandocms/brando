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
    Enum.each(tables, &query!(~s{CREATE TABLE "#{prefix}"."#{&1}" (LIKE public."#{&1}" INCLUDING ALL)}))
    prefix
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

  defp unqualify(nil, _schema), do: nil

  defp unqualify(sql, schema) do
    sql
    |> String.replace(~s("#{schema}".), "")
    |> String.replace("#{schema}.", "")
  end
end
