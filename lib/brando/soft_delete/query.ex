defmodule Brando.SoftDelete.Query do
  @moduledoc """
  Query tools for Soft deletion
  """
  import Ecto.Query
  alias Brando.Repo
  alias Brando.Trait

  require Logger

  @doc """
  Excludes all deleted entries from query
  """
  def exclude_deleted(query), do: from(t in query, where: is_nil(t.deleted_at))

  @doc """
  List all soft delete enabled schemas
  """
  def list_soft_delete_schemas do
    Trait.SoftDelete.list_implementations()
  end

  @doc """
  Check if `schema` is soft deleted
  """
  def soft_delete_schema?(schema), do: schema in list_soft_delete_schemas()

  @doc """
  Count all soft deleted entries per schema
  """
  def count_soft_deletions do
    schemas = list_soft_delete_schemas()

    union_query =
      Enum.reduce(schemas, nil, fn
        schema, nil ->
          from t in schema, select: count(t.id), where: not is_nil(t.deleted_at)

        schema, q ->
          from t in schema, select: count(t.id), where: not is_nil(t.deleted_at), union_all: ^q
      end)

    counts =
      union_query
      |> Repo.all()
      |> Enum.reverse()

    Enum.zip(schemas, counts)
  end

  @doc """
  List all soft deleted entries across schemas
  """
  def list_soft_deleted_entries do
    schemas = list_soft_delete_schemas()
    Enum.flat_map(schemas, &list_soft_deleted_entries(&1))
  end

  @doc """
  List soft deleted entries for `schema`
  """
  def list_soft_deleted_entries(schema) do
    query = from t in schema, where: not is_nil(t.deleted_at), order_by: [desc: t.deleted_at]
    Repo.all(query)
  end

  @unreachable_key {__MODULE__, :unreachable}

  @doc """
  Clean up and delete all expired soft deleted entries
  """
  def clean_up_soft_deletions, do: Enum.map(list_soft_delete_schemas(), &clean_up_schema/1)

  @doc """
  Runs `fun`, one purge of several environments, each calling
  `clean_up_soft_deletions/0`: a video provider one of them could not reach
  is not asked again by the others, until `fun` returns. The provider
  accounts are the installation's, so one that hangs for an environment
  hangs for all, and the soft-delete purger has one deadline for every
  environment. Outside it, each call to `clean_up_soft_deletions/0` is a
  run of its own.
  """
  def as_one_run(fun) when is_function(fun, 0) do
    previous = Process.get(@unreachable_key)
    Process.put(@unreachable_key, [])

    try do
      fun.()
    after
      if previous, do: Process.put(@unreachable_key, previous), else: Process.delete(@unreachable_key)
    end
  end

  # Handle Video schema specially to support remote deletion on purge
  defp clean_up_schema(Brando.Videos.Video = schema) do
    query =
      from t in schema,
        where: fragment("? < current_timestamp - interval '30 day'", t.deleted_at)

    # Check timing per video since different videos may have different providers
    {on_purge, others} =
      query |> Repo.all() |> Enum.split_with(&(Brando.Videos.Uploader.get_delete_timing(&1) == :on_purge))

    # Each row is purged while its video's lock is held, so another
    # environment's purge of the same video, waiting for the lock, no longer
    # finds it among the holders and deletes the video at the provider. The
    # provider is asked once the row is gone, and not when the delete, still
    # filtered on expiry, leaves it: a record with no remote id is restored
    # without the lock, so it may have been restored, or restored and deleted
    # again, since it was read. The row's delete commits with the provider's
    # answer, so a run that dies before the answer keeps the row, and so does
    # a provider that could not answer (`Brando.Videos.Uploader.transient_error?/1`).
    # A video whose holders could not be read (`Brando.Videos.ProviderHoldings`),
    # or whose lock an add or another delete held too long, is still at its
    # provider. Its row stays for the next run to try again; deleting it would
    # leave the provider video behind for good. Only rows the delete removed
    # are counted.
    #
    # Once a provider could not be reached, timed out, or answered with an
    # error only after a long wait (`unreachable?/2`), it is not asked again
    # this run (`as_one_run/1`): each call to a provider that hangs waits out
    # its client's timeout, and the purger has one 30-second deadline for
    # every schema and environment. Its other rows stay for the next run, and
    # the other providers' rows go on. A delete gives up after 5 seconds for
    # each step of the connect (three through a proxy) and 10 for the answer
    # to come, 20 for one that trickles in (`Brando.Videos.Uploaders.ReqOptions`),
    # so one hanging provider leaves the run time for the rest. Several
    # hanging in one run may still use up the deadline: the purger is then
    # stopped, and the rows it did not get to stay for the next run. A
    # provider that answered with an error at once, even a 5xx, may have
    # answered about that one video: it is asked about its other rows.
    unreachable = Process.get(@unreachable_key)
    kept = Map.new(unreachable || [], &{&1, 0})
    {purged, kept} = Enum.reduce(on_purge, {0, kept}, &purge_unless_unreachable(query, &1, &2))
    if unreachable, do: Process.put(@unreachable_key, Map.keys(kept))

    for {type, count} <- kept, count > 0 do
      Logger.warning(
        "#{count} more #{type} #{if count == 1, do: "video", else: "videos"} kept for the next purge, " <>
          "without asking the provider, which could not be reached this run"
      )
    end

    {count, nil} = Repo.delete_all(from t in query, where: t.id in ^Enum.map(others, & &1.id))
    {count + purged, nil}
  end

  defp clean_up_schema(schema) do
    query =
      from t in schema,
        where: fragment("? < current_timestamp - interval '30 day'", t.deleted_at)

    Repo.transaction(fn ->
      purged = if Brando.Activity.logged?(schema), do: Repo.all(query), else: []

      ids = query |> select([t], t.id) |> Repo.all()

      if schema.__trait__(Brando.Trait.Revisioned) do
        Enum.each(ids, &Brando.Revisions.delete_entry_revisions(schema, &1))
      end

      Brando.Notes.entries_purged(schema, ids)

      result = Repo.delete_all(query)
      Enum.each(purged, &Brando.Activity.deleted(&1, :system, false, %{"purged" => true}))
      result
    end)
  end

  # `kept` counts, by provider, the videos left without asking it once it
  # could not be reached.
  defp purge_unless_unreachable(query, video, {purged, kept}) do
    if Map.has_key?(kept, video.type) do
      {purged, Map.update!(kept, video.type, &(&1 + 1))}
    else
      started = System.monotonic_time(:millisecond)

      case purge_video(query, video) do
        {:error, {:retry, reason}} ->
          took = System.monotonic_time(:millisecond) - started
          {purged, if(unreachable?(reason, took), do: Map.put(kept, video.type, 0), else: kept)}

        {:error, reason} when reason in [:holdings_unavailable, :busy, :not_purged] ->
          {purged, kept}

        _purged ->
          {purged + 1, kept}
      end
    end
  end

  # A provider's error answer, a 500 or a 429, comes back within a second or
  # so; one that took 3 seconds or more is a gateway's 502, 503 or 504 after
  # it waited on the provider behind it, and the next call would wait as
  # long. Three seconds leaves a slow network its margin, and is a tenth of
  # the purger's 30 seconds. Tests set it lower, so they need not wait.
  @slow_failure_ms 3_000

  # The provider was not reached, or did not answer in time, or answered
  # only after a long wait: the slow failures. Older Req and Finch pass
  # some of Mint's errors on as they are (`Brando.Videos.Uploader.transient_error?/1`).
  defp unreachable?(%Req.TransportError{}, _took), do: true
  defp unreachable?(%Req.HTTPError{}, _took), do: true
  defp unreachable?(%Mint.TransportError{}, _took), do: true
  defp unreachable?(%Mint.HTTPError{module: Mint.TunnelProxy}, _took), do: true
  defp unreachable?(_reason, took), do: took >= slow_failure_ms()

  defp slow_failure_ms,
    do: :brando |> Application.get_env(__MODULE__, []) |> Keyword.get(:slow_failure_ms, @slow_failure_ms)

  defp purge_video(query, video) do
    Brando.Videos.Uploader.delete_remote(video, fn ->
      match?({1, _}, Repo.delete_all(from t in query, where: t.id == ^video.id))
    end)
  end
end
