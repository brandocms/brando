defmodule Brando.Tenant.ScopedRows do
  @moduledoc """
  The rows in shared tables that belong to one environment by name.

  These tables live in `public` (`Brando.Tenant.SharedTables`) so that replacing
  an environment's schema keeps them, and their `scope` column holds its tenant
  prefix, with no foreign key to the environment. Nothing removes them with the
  environment, and a later site with the same keys would read them, so deleting
  a site or an environment deletes them here too. An assistant conversation's
  messages and runs go with it.

  Rows left by a deletion before this existed are found by `orphaned/0`.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Schema
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @tables ~w(
    forms_submissions
    entry_drafts
    ai_conversations
    ai_runs
    ai_guidance_versions
    content_proposals
    content_proposal_receipts
    content_transfer_receipts
  )

  @public_opts [prefix: "public"]

  @doc "Deletes the rows of the environments with these prefixes. `public` is never one."
  @spec delete([String.t()]) :: :ok
  def delete(prefixes) when is_list(prefixes) do
    prefixes = Enum.filter(prefixes, &Tenant.valid_prefix?/1)

    for table <- @tables do
      Repo.delete_all(from(r in table, where: r.scope in ^prefixes), @public_opts)
    end

    :ok
  end

  @doc """
  The scopes with rows that belong to no environment, with how many rows each
  table holds: `%{"tenant_old_production" => %{"forms_submissions" => 12}}`.

  A scope counts only when it has the form of a tenant prefix, no registered
  environment has it and no schema by that name exists. Without tenancy, or with
  no environment registered at all, there are none.
  """
  @spec orphaned() :: %{String.t() => %{String.t() => pos_integer()}}
  def orphaned do
    case Tenant.enabled?() && registered() do
      registered when is_list(registered) and registered != [] ->
        for table <- @tables,
            {scope, count} <- counts(table),
            Tenant.valid_prefix?(scope),
            scope not in registered,
            not Schema.exists?(scope),
            reduce: %{} do
          found -> Map.update(found, scope, %{table => count}, &Map.put(&1, table, count))
        end

      _ ->
        %{}
    end
  end

  @doc "Deletes what `orphaned/0` finds. Returns the scopes it deleted rows of."
  @spec delete_orphaned() :: [String.t()]
  def delete_orphaned do
    scopes = Map.keys(orphaned())
    Repo.transaction(fn -> delete(scopes) end)
    scopes
  end

  defp registered do
    for site <- Registry.list_sites(), environment <- site.environments, do: Tenant.prefix(site, environment)
  end

  defp counts(table) do
    Repo.all(from(r in table, group_by: r.scope, select: {r.scope, count()}), @public_opts)
  end
end
