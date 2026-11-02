defmodule Brando.Videos.ProviderHoldings do
  @moduledoc """
  Which sites of a multi-site installation hold a provider's video.

  Provider credentials are the installation's, so every site uploads to and
  adds from the same provider accounts. A site holds a remote video while one
  of its environments has a video row for it, deleted or not: uploaded there,
  added from the provider's library, or copied in from another environment.

  The answer is read from the rows themselves, across every current
  environment schema of every site, as `Brando.Media.OrphanCleanup` reads the
  image and file rows. Environment copies and rollbacks bring rows in through
  `pg_dump` and `psql`, which no record of holdings kept on the side would
  see. Archive schemas are not read.

  If one schema cannot be read, the whole answer is an error: the callers
  treat a video whose holders are unknown as held by another site.
  """

  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Videos.Video

  require Logger

  @doc """
  The ids of the sites holding each of `remote_ids`, the provider's ids at the
  `meta` path `path` (`"vimeo.video_id"`). A remote id no site holds is left
  out of the map.
  """
  @spec sites_holding(String.t(), [String.t()], [Site.t()]) ::
          {:ok, %{String.t() => MapSet.t(pos_integer())}} | {:error, term()}
  def sites_holding(path, remote_ids, sites \\ Registry.list_sites())

  def sites_holding(_path, [], _sites), do: {:ok, %{}}

  def sites_holding(path, remote_ids, sites) do
    case schema_queries(sites) do
      {:ok, []} ->
        {:ok, %{}}

      {:ok, selects} ->
        sql = Enum.join(selects, " UNION ALL ")
        keys = String.split(path, ".")

        case Ecto.Adapters.SQL.query(Brando.Repo.repo(), sql, [keys, remote_ids]) do
          {:ok, %{rows: rows}} ->
            {:ok,
             Enum.reduce(rows, %{}, fn [site_id, remote_id], holders ->
               Map.update(holders, remote_id, MapSet.new([site_id]), &MapSet.put(&1, site_id))
             end)}

          {:error, reason} ->
            Logger.warning("Could not read which sites hold provider videos: " <> Exception.message(reason))
            {:error, :holdings_unavailable}
        end

      :error ->
        {:error, :holdings_unavailable}
    end
  end

  # One select per environment schema. Prefixes come from the registry and are
  # checked against the tenant prefix format before they are quoted.
  defp schema_queries(sites) do
    table = Video.__schema__(:source)

    prefixes = for site <- sites, environment <- site.environments, do: {site.id, Tenant.prefix(site, environment)}

    if Enum.all?(prefixes, fn {_site_id, prefix} -> Tenant.valid_prefix?(prefix) end) do
      {:ok,
       Enum.map(prefixes, fn {site_id, prefix} ->
         ~s|SELECT #{site_id}::bigint, meta #>> $1::text[] FROM "#{prefix}"."#{table}" | <>
           ~s|WHERE meta #>> $1::text[] = ANY($2::text[])|
       end)}
    else
      :error
    end
  end
end
