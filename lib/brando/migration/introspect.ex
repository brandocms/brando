defmodule Brando.Migration.Introspect do
  @moduledoc """
  What the database holds at the point a migration runs.

  Some of Brando's upgrade migrations act on the application's own tables,
  found through its current code: its Blueprints, or
  `Brando.Content.Blocks.list_blocks/0`. When an empty database is migrated
  from scratch, those migrations run before the application's own migrations
  have created the tables, so they ask here first and skip what is not there
  yet. The application's own migrations then create those tables in their
  current shape.

  Called from a migration, the functions use the migration's repo and prefix.
  Outside a migration, pass `:repo` (and `:prefix`). With a prefix, only that
  schema is searched. Without one, a table is found the way an unqualified
  name in SQL is, through the connection's `search_path`, which is where the
  migration's unqualified queries will look for it.

  Commands a migration has queued are not seen until it calls `flush/0`.
  """

  @type option :: {:repo, Ecto.Repo.t()} | {:prefix, String.t() | atom()}

  @doc "Whether `table` exists."
  @spec table_exists?(String.t() | atom(), [option()]) :: boolean()
  def table_exists?(table, opts \\ []) do
    {relation, params} = relation(table, opts, 1)

    exists?("SELECT to_regclass(#{relation}) IS NOT NULL", params, opts)
  end

  @doc "Whether `table` exists and has `column`."
  @spec column_exists?(String.t() | atom(), String.t() | atom(), [option()]) :: boolean()
  def column_exists?(table, column, opts \\ []) do
    {relation, params} = relation(table, opts, 2)

    exists?(
      """
      SELECT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass(#{relation}) AND attname = $1
          AND attnum > 0 AND NOT attisdropped
      )
      """,
      [to_string(column) | params],
      opts
    )
  end

  defp exists?(sql, params, opts) do
    %{rows: [[exists?]]} = repo(opts).query!(sql, params, log: false)
    exists?
  end

  # The relation name to_regclass/1 resolves, quoted so that it names the table
  # as given; unqualified without a prefix, so the search_path applies.
  defp relation(table, opts, first) do
    case prefix(opts) do
      nil ->
        {"quote_ident($#{first})", [to_string(table)]}

      prefix ->
        {"quote_ident($#{first + 1}) || '.' || quote_ident($#{first})", [to_string(table), prefix]}
    end
  end

  defp repo(opts), do: Keyword.get_lazy(opts, :repo, &Ecto.Migration.repo/0)

  defp prefix(opts) do
    case Keyword.get(opts, :prefix) || migration_prefix(opts) do
      nil -> nil
      prefix -> to_string(prefix)
    end
  end

  # Ecto.Migration.prefix/0 only answers inside a running migration
  defp migration_prefix(opts) do
    if Keyword.has_key?(opts, :repo), do: nil, else: Ecto.Migration.prefix()
  end
end
