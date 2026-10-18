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

  Called from a migration, the functions use the migration's repo and prefix
  (`public` without one). Outside a migration, pass `:repo` (and `:prefix`).

  Commands a migration has queued are not seen until it calls `flush/0`.
  """

  @type option :: {:repo, Ecto.Repo.t()} | {:prefix, String.t() | atom()}

  @doc "Whether `table` exists."
  @spec table_exists?(String.t() | atom(), [option()]) :: boolean()
  def table_exists?(table, opts \\ []) do
    exists?(
      "SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = $2",
      [prefix(opts), to_string(table)],
      opts
    )
  end

  @doc "Whether `table` exists and has `column`."
  @spec column_exists?(String.t() | atom(), String.t() | atom(), [option()]) :: boolean()
  def column_exists?(table, column, opts \\ []) do
    exists?(
      """
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = $1 AND table_name = $2 AND column_name = $3
      """,
      [prefix(opts), to_string(table), to_string(column)],
      opts
    )
  end

  defp exists?(sql, params, opts) do
    %{num_rows: rows} = repo(opts).query!(sql, params, log: false)
    rows > 0
  end

  defp repo(opts), do: Keyword.get_lazy(opts, :repo, &Ecto.Migration.repo/0)

  defp prefix(opts) do
    case Keyword.fetch(opts, :prefix) do
      {:ok, prefix} when not is_nil(prefix) -> to_string(prefix)
      _ -> to_string(migration_prefix(opts) || "public")
    end
  end

  # Ecto.Migration.prefix/0 only answers inside a running migration
  defp migration_prefix(opts) do
    if Keyword.has_key?(opts, :repo), do: nil, else: Ecto.Migration.prefix()
  end
end
