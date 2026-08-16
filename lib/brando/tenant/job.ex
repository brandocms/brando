defmodule Brando.Tenant.Job do
  @moduledoc """
  Carries tenant context across background-job process boundaries.

  Oban serializes jobs in the shared `public` schema and executes them in a new
  process. The process-local prefix used by requests and LiveViews must
  therefore be copied into tenant-owned job arguments and restored before the
  worker touches content or media.
  """

  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @prefix_key "tenant_prefix"

  @doc "Adds the current tenant prefix to job arguments when tenancy is enabled."
  @spec attach(map()) :: map()
  def attach(args) when is_map(args) do
    case {Tenant.mode(), Tenant.current_prefix()} do
      {:none, nil} -> args
      {_enabled_mode, prefix} when is_binary(prefix) -> Map.put(args, @prefix_key, prefix)
      {_enabled_mode, nil} -> raise ArgumentError, "tenant-owned jobs require a current tenant prefix"
    end
  end

  @doc "Runs a tenant-owned job under the prefix captured when it was enqueued."
  @spec run(Oban.Job.t() | map(), (-> result)) :: result | {:cancel, atom()} when result: var
  def run(%Oban.Job{args: args}, fun), do: run(args, fun)

  def run(args, fun) when is_map(args) and is_function(fun, 0) do
    case {Tenant.mode(), prefix_from(args)} do
      {:none, _prefix} ->
        fun.()

      {_enabled_mode, prefix} when is_binary(prefix) ->
        if Tenant.valid_prefix?(prefix),
          do: Tenant.with_prefix(prefix, fun),
          else: {:cancel, :invalid_tenant_prefix}

      {_enabled_mode, nil} ->
        {:cancel, :missing_tenant_prefix}
    end
  end

  @doc "Runs a function once per environment belonging to every active site."
  @spec each_active_environment(:all | :live, (-> result)) :: [result] when result: var
  def each_active_environment(scope, fun)
      when scope in [:all, :live] and is_function(fun, 0) do
    if Tenant.enabled?() do
      Registry.list_sites()
      |> Enum.filter(&(&1.status == :active))
      |> Enum.flat_map(&run_for_site(&1, scope, fun))
    else
      [fun.()]
    end
  end

  @doc "Returns the current job-argument fragment used to scope shared Oban queries."
  @spec context_fragment() :: map()
  def context_fragment do
    %{}
    |> attach()
    |> Map.take([@prefix_key])
  end

  defp prefix_from(args), do: Map.get(args, @prefix_key) || Map.get(args, :tenant_prefix)

  defp run_for_site(site, scope, fun) do
    site.environments
    |> select_environments(scope)
    |> Enum.map(fn environment ->
      site
      |> Tenant.prefix(environment)
      |> Tenant.with_prefix(fun)
    end)
  end

  defp select_environments(environments, :all), do: environments
  defp select_environments(environments, :live), do: Enum.filter(environments, & &1.live)
end
