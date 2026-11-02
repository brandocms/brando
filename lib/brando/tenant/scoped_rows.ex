defmodule Brando.Tenant.ScopedRows do
  @moduledoc """
  The rows in shared tables that belong to one environment by name.

  These tables live in `public` (`Brando.Tenant.SharedTables`) so that replacing
  an environment's schema keeps them, with no foreign key to the environment.
  Nothing removes them with the environment, and a later site with the same keys
  would read them, so deleting a site or an environment deletes them here too. An
  assistant conversation's messages and runs go with it.

  Form submissions and entry drafts hold the tenant prefix in `scope`. The other
  tables hold `Brando.Content.Definition.References.scope/0`: a digest of the
  database's host, port and name and the tenant prefix. Rows written before the
  database moved hold another digest, and these functions do not reach them.

  Rows left by a deletion before this existed are found by `orphaned/0`. A digest
  says nothing by itself, and one matching nothing known may be a moved database's
  live row, so only a prefix stored in `forms_submissions`, `entry_drafts` or
  `ai_guidance_versions` makes a scope a candidate. Digest rows of a deleted site
  with no such trace stay.
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.References
  alias Brando.Environments
  alias Brando.Environments.Schema
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup

  @prefix_tables ~w(forms_submissions entry_drafts)

  @digest_tables ~w(
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
    prefixes |> Enum.filter(&Tenant.valid_prefix?/1) |> delete_rows()
    :ok
  end

  @doc """
  The scopes with rows that belong to no environment, with how many rows each
  table holds: `%{"tenant_old_production" => %{"forms_submissions" => 12}}`.

  A scope counts only when it is stored as a tenant prefix in `forms_submissions`,
  `entry_drafts` or `ai_guidance_versions`, no registered environment has it and
  no schema by that name exists. Without tenancy, or with no environment registered
  at all, there are none.
  """
  @spec orphaned() :: %{String.t() => %{String.t() => pos_integer()}}
  def orphaned do
    case registered() do
      [] ->
        %{}

      registered ->
        for scope <- candidates(),
            orphan?(scope, registered),
            counts = counts(scope),
            counts != %{},
            into: %{},
            do: {scope, counts}
    end
  end

  @doc "Deletes what `orphaned/0` finds. Returns the scopes it deleted rows of."
  @spec delete_orphaned() :: [String.t()]
  def delete_orphaned, do: orphaned() |> Map.keys() |> delete_orphaned()

  @doc """
  Deletes the rows of those of `scopes` that are still orphaned, one at a time,
  holding the locks that creating its site or environment takes. Returns the scopes
  it deleted rows of.
  """
  @spec delete_orphaned([String.t()]) :: [String.t()]
  def delete_orphaned(scopes) when is_list(scopes), do: Enum.filter(scopes, &delete_if_orphaned/1)

  defp delete_if_orphaned(scope) do
    case Tenant.site_key_of(scope) do
      nil -> false
      site_key -> Lock.with(Setup.lifecycle_lock_key(site_key), fn -> delete_under_lifecycle_lock(scope, site_key) end)
    end
  end

  defp delete_under_lifecycle_lock(scope, site_key) do
    case Registry.get_site_by_key(site_key) do
      nil -> delete_when_orphaned(scope, nil)
      site -> Environments.with_site_lock(site, fn -> delete_when_orphaned(scope, site) end)
    end
  end

  defp delete_when_orphaned(scope, site) do
    {:ok, deleted} =
      Repo.transaction(fn ->
        lock_site_row(site)
        if orphan?(scope, registered()), do: delete_rows([scope]), else: 0
      end)

    deleted > 0
  end

  # Creating an environment takes neither lock, but its row's foreign key waits on
  # this until the deletion commits, so it sees none of what it deletes.
  defp lock_site_row(nil), do: nil

  defp lock_site_row(site) do
    Repo.one(from(s in "sites", where: s.id == ^site.id, select: s.id, lock: "FOR UPDATE"), @public_opts)
  end

  defp delete_rows(prefixes) do
    digests = digests(prefixes)

    Enum.sum(for table <- @prefix_tables, do: delete_from(table, prefixes)) +
      Enum.sum(for table <- @digest_tables, do: delete_from(table, digests))
  end

  defp delete_from(table, scopes) do
    from(r in table, where: r.scope in ^scopes) |> Repo.delete_all(@public_opts) |> elem(0)
  end

  # Without tenancy every prefix digests as `public`, which is live.
  defp digests(prefixes) do
    if Tenant.enabled?(), do: Enum.map(prefixes, &digest/1), else: []
  end

  defp digest(prefix), do: Tenant.with_prefix(prefix, &References.scope/0)

  # Empty when nothing can be told apart from a live environment.
  defp registered do
    if Tenant.enabled?() do
      for site <- Registry.list_sites(), environment <- site.environments, do: Tenant.prefix(site, environment)
    else
      []
    end
  end

  defp orphan?(_scope, []), do: false

  defp orphan?(scope, registered) do
    Tenant.valid_prefix?(scope) and scope not in registered and not Schema.exists?(scope)
  end

  defp candidates do
    stored =
      for table <- @prefix_tables,
          scope <- Repo.all(from(r in table, distinct: true, select: r.scope), @public_opts),
          do: scope

    guidance =
      Repo.all(
        from(r in "ai_guidance_versions", where: not is_nil(r.prefix), distinct: true, select: r.prefix),
        @public_opts
      )

    Enum.uniq(stored ++ guidance)
  end

  defp counts(scope) do
    digest = digest(scope)

    for {table, stored} <- Enum.map(@prefix_tables, &{&1, scope}) ++ Enum.map(@digest_tables, &{&1, digest}),
        count = Repo.aggregate(from(r in table, where: r.scope == ^stored), :count, @public_opts),
        count > 0,
        into: %{},
        do: {table, count}
  end
end
