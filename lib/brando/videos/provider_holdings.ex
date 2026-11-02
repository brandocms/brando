defmodule Brando.Videos.ProviderHoldings do
  @moduledoc """
  Which sites, and which of their environments, hold a provider's video.

  Provider credentials are the installation's, so every site uploads to and
  adds from the same provider accounts, and every environment of a site
  copied from another holds the same remote videos. An environment holds a
  remote video while it has a video row for it, deleted or not: uploaded
  there, added from the provider's library, or copied in from another
  environment. A site holds it while one of its environments does.

  The answer is read from the rows themselves, across every current
  environment schema of every site, as `Brando.Media.OrphanCleanup` reads the
  image and file rows. Environment copies and rollbacks bring rows in through
  `pg_dump` and `psql`, which no record of holdings kept on the side would
  see. Archive schemas are not read.

  A schema without a video table, while its environment is created or
  copied, holds nothing. If one video table cannot be read, the whole answer
  is an error: the callers treat a video whose holders are unknown as held
  elsewhere.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Videos.Video

  require Logger

  @lock_timeout 30_000
  @lock_poll_interval 100

  @typedoc """
  A `meta` path and the value there that ties a video row to a remote video:
  `{"mux.upload_id", "abc"}`.
  """
  @type holding_key :: {String.t(), String.t()}

  @doc """
  The ids of the sites holding each of `remote_ids`, the provider's ids at the
  `meta` path `path` (`"vimeo.video_id"`). A remote id no site holds is left
  out of the map.

  A remote id can come as `{remote_id, holding_keys}`, when a row may hold the
  video before it has the id at `path`: a Mux upload has only its
  `mux.upload_id` until Mux reports the asset. A row with any of the keys
  holds it.

  An environment whose schema has no video table yet, while it is created or
  copied, holds nothing.
  """
  @spec sites_holding(String.t(), [String.t() | {String.t(), [holding_key()]}], [Site.t()]) ::
          {:ok, %{String.t() => MapSet.t(pos_integer())}} | {:error, term()}
  def sites_holding(path, remote_ids, sites \\ Registry.list_sites()) do
    with {:ok, holders} <- environments_holding(path, remote_ids, sites) do
      {:ok, Map.new(holders, fn {remote_id, environments} -> {remote_id, MapSet.new(environments, &elem(&1, 0))} end)}
    end
  end

  @doc """
  The environments holding each of `remote_ids`, as `{site_id, prefix,
  deleted?}` with the environment's schema prefix, read as `sites_holding/3`
  reads the sites. `deleted?` is true when every row the environment has for
  the video is soft-deleted. A remote id no environment holds is left out of
  the map.
  """
  @spec environments_holding(String.t(), [String.t() | {String.t(), [holding_key()]}], [Site.t()]) ::
          {:ok, %{String.t() => MapSet.t({pos_integer(), String.t(), boolean()})}} | {:error, term()}
  def environments_holding(path, remote_ids, sites \\ Registry.list_sites())

  def environments_holding(_path, [], _sites), do: {:ok, %{}}

  def environments_holding(path, remote_ids, sites) do
    with {:ok, prefixes} <- prefixes(sites),
         {:ok, prefixes} <- readable(prefixes) do
      read_holdings(prefixes, matches(path, remote_ids))
    end
  end

  @doc """
  Whether the current environment has a live record of the remote video,
  the provider's id `remote_id` at the `meta` path `path`, other than the
  record with the id `except_id`.
  """
  @spec recorded_here?(String.t(), String.t(), pos_integer() | nil) :: boolean()
  def recorded_here?(path, remote_id, except_id \\ nil) do
    keys = String.split(path, ".")

    query =
      from(v in Video,
        where: is_nil(v.deleted_at) and fragment("?#>>? = ?", v.meta, ^keys, ^remote_id),
        select: true,
        limit: 1
      )

    query = if except_id, do: from(v in query, where: v.id != ^except_id), else: query
    Brando.Repo.one(query) == true
  end

  @doc """
  Runs `fun` holding the lock of one remote video, the provider's id
  `remote_id` at the `meta` path `path`, and returns its result.

  A delete at the provider and an add of the same video take it around their
  holdings check and their provider call, so an add that waits out a delete
  sees the deleting site's row still there, or the provider's 404, and a
  delete that waits out an add sees the added row.

  Outside a transaction, the lock is the database session's, taken on a
  connection checked out for `fun` and given back when it returns. `fun`'s
  queries then commit as they run, and the holdings read does not keep the
  video tables locked while the provider is asked, which would hold up an
  environment copy's `DROP SCHEMA`. Inside the caller's transaction, the lock
  lasts until that transaction ends, so what it writes is committed before
  another delete or add reads the holdings.

  The lock is waited for up to 30 seconds (`config :brando,
  Brando.Videos.ProviderHoldings, lock_timeout: milliseconds`), then
  `{:error, :busy}` is returned and `fun` does not run.
  """
  @spec with_video_lock(String.t(), String.t(), (-> result)) :: result | {:error, :busy | :holdings_unavailable}
        when result: term()
  def with_video_lock(path, remote_id, fun) do
    repo = Brando.Repo.repo()
    key = "brando:provider_video:#{path}:#{remote_id}"
    deadline = System.monotonic_time(:millisecond) + lock_timeout()

    if repo.in_transaction?() do
      with :ok <- acquire("pg_try_advisory_xact_lock", key, deadline), do: fun.()
    else
      # No checkout deadline: the pool would close the connection when one
      # ran out, and the session's lock with it, while `fun` still runs. The
      # wait has its own limit, and the provider clients their own timeouts.
      repo.checkout(fn -> with_session_lock(repo, key, deadline, fun) end, timeout: :infinity)
    end
  end

  defp with_session_lock(repo, key, deadline, fun) do
    with :ok <- acquire("pg_try_advisory_lock", key, deadline) do
      try do
        fun.()
      after
        Ecto.Adapters.SQL.query(repo, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
      end
    end
  end

  # Tried rather than waited for: a wait longer than the query timeout would
  # raise in the editor's LiveView, or in the delete's transaction.
  defp acquire(function, key, deadline) do
    case query("SELECT #{function}(hashtextextended($1, 0))", [key], "Could not lock a provider video: ") do
      {:ok, %{rows: [[true]]}} ->
        :ok

      {:ok, %{rows: [[false]]}} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(@lock_poll_interval)
          acquire(function, key, deadline)
        else
          {:error, :busy}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp lock_timeout do
    :brando |> Application.get_env(__MODULE__, []) |> Keyword.get(:lock_timeout, @lock_timeout)
  end

  # `{path, [{value, remote_id}]}` for each path a row may hold a video at.
  defp matches(path, remote_ids) do
    for item <- remote_ids,
        {remote_id, keys} = with_keys(item),
        {key_path, value} <- [{path, remote_id} | keys],
        is_binary(value),
        uniq: true do
      {key_path, value, remote_id}
    end
    |> Enum.group_by(&elem(&1, 0), fn {_path, value, remote_id} -> {value, remote_id} end)
    |> Enum.to_list()
  end

  defp with_keys({remote_id, keys}), do: {remote_id, keys}
  defp with_keys(remote_id), do: {remote_id, []}

  # Prefixes come from the registry and are checked against the tenant prefix
  # format before they are quoted, as identifiers and as the literal naming
  # the environment.
  defp prefixes(sites) do
    prefixes = for site <- sites, environment <- site.environments, do: {site.id, Tenant.prefix(site, environment)}

    if Enum.all?(prefixes, fn {_site_id, prefix} -> Tenant.valid_prefix?(prefix) end),
      do: {:ok, prefixes},
      else: {:error, :holdings_unavailable}
  end

  # An environment is registered before its schema is made, and a copy drops
  # and rebuilds the target's. Until the video table is there, the schema
  # holds nothing, and reading it would fail for every site.
  defp readable([]), do: {:ok, []}

  defp readable(prefixes) do
    schemas = prefixes |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    case query("SELECT schemaname FROM pg_tables WHERE tablename = $1 AND schemaname = ANY($2::text[])", [
           Video.__schema__(:source),
           schemas
         ]) do
      {:ok, %{rows: rows}} ->
        present = rows |> List.flatten() |> MapSet.new()
        {:ok, Enum.filter(prefixes, fn {_site_id, prefix} -> prefix in present end)}

      {:error, _reason} = error ->
        error
    end
  end

  defp read_holdings([], _matches), do: {:ok, %{}}
  defp read_holdings(_prefixes, []), do: {:ok, %{}}

  # One select per environment schema and path.
  defp read_holdings(prefixes, matches) do
    table = Video.__schema__(:source)

    {selects, params} =
      matches
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {{path, pairs}, index}, {selects, params} ->
        [keys, values, remote_ids] = Enum.map([3 * index + 1, 3 * index + 2, 3 * index + 3], &"$#{&1}")

        path_selects =
          Enum.map(prefixes, fn {site_id, prefix} ->
            ~s|SELECT #{site_id}::bigint, '#{prefix}'::text, k.remote_id, v.deleted_at IS NOT NULL | <>
              ~s|FROM "#{prefix}"."#{table}" v | <>
              ~s|JOIN unnest(#{values}::text[], #{remote_ids}::text[]) AS k(value, remote_id) | <>
              ~s|ON v.meta #>> #{keys}::text[] = k.value|
          end)

        {selects ++ path_selects,
         params ++ [String.split(path, "."), Enum.map(pairs, &elem(&1, 0)), Enum.map(pairs, &elem(&1, 1))]}
      end)

    case query(Enum.join(selects, " UNION ALL "), params) do
      {:ok, %{rows: rows}} ->
        {:ok,
         rows
         |> Enum.reduce(%{}, fn [site_id, prefix, remote_id, deleted?], holders ->
           Map.update(holders, {remote_id, site_id, prefix}, deleted?, &(&1 and deleted?))
         end)
         |> Enum.reduce(%{}, fn {{remote_id, site_id, prefix}, deleted?}, holders ->
           holder = {site_id, prefix, deleted?}
           Map.update(holders, remote_id, MapSet.new([holder]), &MapSet.put(&1, holder))
         end)}

      {:error, _reason} = error ->
        error
    end
  end

  # Inside a transaction, such as a delete's, a failed read rolls back to
  # before it rather than aborting the caller's work.
  defp query(sql, params, failure \\ "Could not read which environments hold provider videos: ") do
    repo = Brando.Repo.repo()
    opts = if repo.in_transaction?(), do: [mode: :savepoint], else: []

    case Ecto.Adapters.SQL.query(repo, sql, params, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.warning(failure <> Exception.message(reason))
        {:error, :holdings_unavailable}
    end
  end
end
