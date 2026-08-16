defmodule Brando.Tenant.PublicDataMigrator.Postgres do
  @moduledoc false

  @behaviour Brando.Tenant.PublicDataMigrator

  alias Brando.Environments.SchemaCloner.Postgres, as: SchemaCloner

  @shared_tables ~w(
    environments
    environment_operation_logs
    oban_jobs
    schema_migrations
    site_asset_sets
    sites
    sites_previews
    uploads_pending_intents
    user_sites
    user_tokens
    users
    users_tokens
  )

  @safe_table ~r/^[a-z0-9_]+$/

  @impl true
  def migrate(source_prefix, target_prefix) do
    with {:ok, tables} <- copyable_tables(source_prefix, target_prefix),
         true <- tables != [],
         {:ok, dump} <- SchemaCloner.dump_schema(source_prefix, dump_args(source_prefix, tables)),
         {:ok, rewritten_dump} <- SchemaCloner.rewrite_schema(dump, source_prefix, target_prefix),
         :ok <- SchemaCloner.restore_dump(rewritten_dump) do
      :ok
    else
      false -> {:error, :no_copyable_public_tables}
      {:error, _reason} = error -> error
    end
  end

  defp copyable_tables(source_prefix, target_prefix) do
    sql = """
    SELECT target.tablename
    FROM pg_tables AS target
    INNER JOIN pg_tables AS source
      ON source.tablename = target.tablename
     AND source.schemaname = $1
    WHERE target.schemaname = $2
    ORDER BY target.tablename
    """

    case Ecto.Adapters.SQL.query(Brando.Repo.repo(), sql, [source_prefix, target_prefix]) do
      {:ok, %{rows: rows}} ->
        tables =
          rows
          |> Enum.map(&List.first/1)
          |> Enum.reject(&(&1 in @shared_tables))

        if Enum.all?(tables, &Regex.match?(@safe_table, &1)),
          do: {:ok, tables},
          else: {:error, :unsafe_public_table_name}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dump_args(source_prefix, tables) do
    ["--data-only"] ++ Enum.map(tables, &"--table=#{source_prefix}.#{&1}")
  end
end
