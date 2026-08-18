defmodule Brando.Environments.StructureCloner.Postgres do
  @moduledoc """
  Clones table structure between PostgreSQL schemas with `pg_dump` and `psql`.

  The dump is restricted to the source schema's tenant tables, so shared tables
  and the sequences they own are never recreated in the target.

  Qualified identifiers are then rewritten against an allow-list of the objects
  the dump actually creates — the requested tables plus the sequences it declares.
  Everything else keeps its original qualifier, which is what a schema-only dump
  needs: with `search_path` emptied, pg_dump qualifies enum types, extension
  types like `citext`, and trigger functions too, and all of those live in the
  source schema and are used from the target rather than copied into it. A
  foreign key to `public.users` is left alone for the same reason.
  """

  @behaviour Brando.Environments.StructureCloner

  alias Brando.Environments.SchemaCloner.Postgres, as: SchemaCloner
  alias Brando.Tenant.SharedTables

  @safe_identifier ~r/^[a-z0-9_-]+$/

  @impl true
  def clone_structure(source_prefix, target_prefix) do
    with :ok <- validate_identifier(target_prefix),
         {:ok, tables} <- tenant_tables(source_prefix),
         :ok <- ensure_any(tables, source_prefix),
         {:ok, dump} <- SchemaCloner.dump_schema(source_prefix, dump_args(source_prefix, tables)),
         {:ok, rewritten} <- rewrite(dump, source_prefix, target_prefix, tables) do
      SchemaCloner.restore_dump(rewritten)
    end
  end

  @doc "Lists the tables in `prefix` that belong inside a tenant schema."
  @spec tenant_tables(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def tenant_tables(prefix) do
    sql = "SELECT tablename FROM pg_tables WHERE schemaname = $1 ORDER BY tablename"

    case Ecto.Adapters.SQL.query(Brando.Repo.repo(), sql, [prefix]) do
      {:ok, %{rows: rows}} ->
        tables = rows |> Enum.map(&List.first/1) |> Enum.reject(&SharedTables.member?/1)

        case Enum.filter(tables, &String.contains?(&1, ~s|"|)) do
          [] -> {:ok, tables}
          unquotable -> {:error, {:unsafe_source_table_name, unquotable}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Quotes a PostgreSQL identifier for use in a `pg_dump` object pattern.

  `--table` takes a pattern, not a literal: an unquoted pattern is case-folded
  and treats `*`, `?`, and `[` as wildcards, so an unquoted mixed-case name
  matches nothing and the table is silently left out of the dump. Quoting turns
  both behaviours off.
  """
  @spec quote_identifier(String.t()) :: String.t()
  def quote_identifier(name), do: ~s|"| <> name <> ~s|"|

  defp ensure_any([], source_prefix), do: {:error, {:no_tenant_tables, source_prefix}}
  defp ensure_any(_tables, _source_prefix), do: :ok

  defp dump_args(source_prefix, tables) do
    schema = quote_identifier(source_prefix)
    ["--schema-only"] ++ Enum.map(tables, &"--table=#{schema}.#{quote_identifier(&1)}")
  end

  @doc """
  Requalifies the objects this dump creates into `target_prefix`.

  Only `tables` and the sequences the dump declares are moved. Types, functions,
  and shared tables keep `source_prefix`, because the target uses them where they
  are instead of owning a copy.

  A schema-only dump carries no `COPY` payload, so this is a plain substitution
  over qualified identifiers with no data section to skip.
  """
  @spec rewrite(String.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, String.t()} | {:error, term()}
  def rewrite(dump, source_prefix, target_prefix, tables) do
    pattern = ~r/"#{Regex.escape(source_prefix)}"\."([^"]+)"/
    owned = owned_objects(dump, source_prefix, tables)

    rewritten =
      Regex.replace(pattern, dump, fn match, name ->
        if MapSet.member?(owned, name), do: ~s|"#{target_prefix}"."#{name}"|, else: match
      end)

    case residual_objects(rewritten, pattern, owned) do
      [] -> {:ok, rewritten}
      residual -> {:error, {:unrewritten_objects, residual}}
    end
  end

  defp owned_objects(dump, source_prefix, tables) do
    sequences =
      ~r/CREATE SEQUENCE "#{Regex.escape(source_prefix)}"\."([^"]+)"/
      |> Regex.scan(dump, capture: :all_but_first)
      |> Enum.map(&List.first/1)

    tables |> Enum.concat(sequences) |> MapSet.new()
  end

  defp residual_objects(sql, pattern, owned) do
    pattern
    |> Regex.scan(sql, capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> Enum.filter(&MapSet.member?(owned, &1))
    |> Enum.uniq()
  end

  defp validate_identifier(identifier) do
    if is_binary(identifier) and Regex.match?(@safe_identifier, identifier) and
         byte_size(identifier) <= 63 do
      :ok
    else
      {:error, {:invalid_schema_identifier, identifier}}
    end
  end
end
