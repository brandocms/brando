defmodule Brando.Test.Committed do
  @moduledoc """
  Runs a test's queries outside the sandbox, each process on a connection of
  its own, and deletes what it committed afterwards. For a test of code that
  holds one connection while another process works on a second, which a
  sandbox, one connection per test, cannot give (a snapshot rendered under
  the site's asset lock). Only in a module that is not async: the repo's
  mode is the whole run's.

      setup do
        Brando.Test.Committed.start()
      end

  `start/0` marks where each `public` table is, puts the repo in `:auto`
  mode, and on exit deletes the rows above the mark (by id, or by
  `inserted_at` in a table without an integer id), children before their
  parents, and puts the sandbox back.
  """

  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  def start do
    Sandbox.mode(Repo, :auto)
    mark = mark()

    ExUnit.Callbacks.on_exit(fn ->
      clean(mark)
      Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  defp mark do
    %{rows: [[at]]} = Repo.query!("SELECT (now() AT TIME ZONE 'utc')::timestamp")

    %{rows: rows} =
      Repo.query!("""
      SELECT t.table_name, i.data_type, a.column_name
      FROM information_schema.tables t
      LEFT JOIN information_schema.columns i
        ON i.table_schema = t.table_schema AND i.table_name = t.table_name AND i.column_name = 'id'
      LEFT JOIN information_schema.columns a
        ON a.table_schema = t.table_schema AND a.table_name = t.table_name AND a.column_name = 'inserted_at'
      WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND t.table_name <> 'schema_migrations'
      """)

    for [table, id_type, inserted_at] <- rows, deletion = deletion(table, id_type, inserted_at, at), into: %{} do
      {table, deletion}
    end
  end

  defp deletion(table, id_type, _inserted_at, _at) when id_type in ["bigint", "integer"] do
    %{rows: [[max]]} = Repo.query!(~s|SELECT coalesce(max(id), 0) FROM public."#{table}"|)
    {~s|DELETE FROM public."#{table}" WHERE id > $1|, [max]}
  end

  defp deletion(table, _id_type, "inserted_at", at),
    do: {~s|DELETE FROM public."#{table}" WHERE inserted_at >= $1|, [at]}

  # A join table without either goes with its rows' parents
  defp deletion(_table, _id_type, _inserted_at, _at), do: nil

  # In passes: a row still referred to is deleted in a later one
  defp clean(pending) when pending == %{}, do: :ok

  defp clean(pending) do
    left = Map.reject(pending, fn {_table, {sql, params}} -> deleted?(sql, params) end)

    if map_size(left) == map_size(pending),
      do: raise("Brando.Test.Committed could not delete the rows of #{inspect(Map.keys(left))}")

    clean(left)
  end

  defp deleted?(sql, params) do
    Repo.query!(sql, params)
    true
  rescue
    error in Postgrex.Error ->
      if error.postgres.code == :foreign_key_violation, do: false, else: reraise(error, __STACKTRACE__)
  end
end
