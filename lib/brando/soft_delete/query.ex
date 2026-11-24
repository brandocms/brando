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
  Clean up and delete all expired soft deleted entries, one schema at a time.

  A schema whose purge fails is logged and returns `{:error, schema}`, and
  the others are still purged. Before a schema's expired rows are deleted, its
  context's optional `before_purge(schema, ids)` runs in the same transaction,
  to clear what still refers to them (`Brando.Pages.before_purge/2`). A row
  that something else still refers to is kept for the next run, and is not a
  failure.
  """
  def clean_up_soft_deletions, do: Enum.map(list_soft_delete_schemas(), &try_clean_up_schema/1)

  defp try_clean_up_schema(schema) do
    case clean_up_schema(schema) do
      {:error, reason} ->
        Logger.error(
          "[Brando.SoftDelete] Purging #{inspect(schema)}#{environment()} failed: #{describe_rollback(reason)}"
        )

        {:error, schema}

      result ->
        result
    end
  rescue
    error ->
      Logger.error(
        "[Brando.SoftDelete] Purging #{inspect(schema)}#{environment()} failed: #{describe_error(error, __STACKTRACE__)}"
      )

      {:error, schema}
  end

  # A hook's rollback, by its kind only: it may hold a row's values
  defp describe_rollback(%Ecto.Changeset{data: %struct{}}), do: "rolled back with an invalid #{inspect(struct)}"
  defp describe_rollback(reason) when is_atom(reason), do: "rolled back with #{inspect(reason)}"
  defp describe_rollback(_reason), do: "rolled back"

  @doc "Where a purge runs, for its log lines: the site and environment, if any."
  def environment do
    case {Brando.Tenant.current_site_key(), Brando.Tenant.current_environment_key()} do
      {nil, nil} -> ""
      {site, environment} -> " in site #{site}, environment #{environment}"
    end
  end

  @doc """
  An error of a purge, for its log line: a database error's code, table and
  constraint, without its message, which may quote a row's values; any other
  error's message and `stacktrace`.
  """
  def describe_error(%Postgrex.Error{postgres: %{code: code} = postgres}, _stacktrace) do
    [code, postgres[:table], postgres[:constraint]] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  def describe_error(error, stacktrace), do: Exception.format(:error, error, stacktrace)

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
      # Locked, so a restore waits for the purge, and deleted by id, so the
      # rows deleted are the rows the hook was given
      ids = query |> select([t], t.id) |> lock("FOR UPDATE") |> Repo.all()
      purged = if Brando.Activity.logged?(schema), do: Repo.all(from t in schema, where: t.id in ^ids), else: []

      deleted = purge_ids(schema, ids)

      for entry <- purged, entry.id in deleted do
        Brando.Activity.deleted(entry, :system, false, %{"purged" => true})
      end

      {length(deleted), nil}
    end)
  end

  @doc """
  Deletes the entries `ids` of `schema` that are in the trash for good, now,
  in the caller's transaction: what the scheduled purge does for an expired
  row (revisions, notes, translation membership through
  `Brando.Translations.entries_deleted/2`, the context's `before_purge/2`), and
  the activity log records `actor` deleting each one, with `details` saying
  why. Rows not in the trash are left.

  Returns `:ok`, or `{:error, {:referenced, constraint}}` when something still
  refers to one of them: the purge is rolled back to a savepoint, nothing is
  deleted, and the transaction goes on. Run it inside `Repo.transaction/1`.
  """
  def purge_entries(schema, ids, actor, details \\ %{}) do
    entries =
      from(t in schema, where: t.id in ^ids and not is_nil(t.deleted_at), lock: "FOR UPDATE")
      |> Repo.all()

    trashed = Enum.map(entries, & &1.id)

    case in_savepoint(fn -> purge_rows_now(schema, trashed) end) do
      :ok ->
        for entry <- entries, Brando.Activity.logged?(schema) do
          Brando.Activity.deleted(entry, actor, false, Map.put(details, "purged", true))
        end

        :ok

      {:referenced, constraint} ->
        {:error, {:referenced, constraint}}
    end
  end

  @doc """
  Deletes the entry `id` of `schema` from the trash for good, for `actor`, in
  a transaction of its own: Delete permanently in a listing's trash.

  Only a row still in the trash with `deleted_at` as the person saw it goes,
  and only when `actor` may delete it for good (`may_purge?/2`), both decided
  on the locked row. It goes as `purge_entries/4` deletes it, and a video
  whose provider deletes it on purge also as the scheduled purge deletes it
  (`Brando.Videos.Uploader.delete_remote/2`).

  Returns `:ok`, or `{:error, reason}` and nothing is deleted: `:not_in_trash`
  (restored, already deleted, or trashed again since), `:forbidden`,
  `{:referenced, constraint}`, or for a video its provider's
  `{:retry, reason}`, `:busy` or `:holdings_unavailable`.
  """
  def purge_entry(_schema, _id, nil, _actor), do: {:error, :not_in_trash}

  def purge_entry(schema, id, deleted_at, actor) do
    case video_deleted_on_purge(schema, id, deleted_at) do
      nil -> purge_trashed_in_transaction(schema, id, deleted_at, actor)
      video -> purge_video_entry(video, actor)
    end
  end

  @doc """
  Whether `actor` may delete `entry`, in the trash, for good: the delete
  permission on it, and for one trashed while published the publish
  permission too, as trashing it took. It keeps that status in the trash.
  """
  def may_purge?(actor, entry) do
    alias Brando.Authorization.Boundary

    Boundary.authorize(actor, :delete, entry) == :ok and
      (Map.get(entry, :status) != :published or Boundary.authorize(actor, :publish, entry) == :ok)
  end

  defp purge_trashed_in_transaction(schema, id, deleted_at, actor) do
    Repo.transaction(fn ->
      case Brando.Authorization.Boundary.run(actor, :delete, schema, &purge_trashed(schema, id, deleted_at, &1)) do
        :ok -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  # In the caller's transaction, and rolls nothing back itself: a refusal
  # has written nothing, and a reference is rolled back to its savepoint
  defp purge_trashed(schema, id, deleted_at, actor) do
    trashed = Repo.one(from t in schema, where: t.id == ^id and t.deleted_at == ^deleted_at, lock: "FOR UPDATE")

    cond do
      is_nil(trashed) -> {:error, :not_in_trash}
      not may_purge?(actor, trashed) -> {:error, :forbidden}
      true -> purge_entries(schema, [trashed.id], actor)
    end
  end

  defp video_deleted_on_purge(Brando.Videos.Video, id, deleted_at) do
    video = Repo.one(from v in Brando.Videos.Video, where: v.id == ^id and v.deleted_at == ^deleted_at)
    if video && Brando.Videos.Uploader.get_delete_timing(video) == :on_purge, do: video
  end

  defp video_deleted_on_purge(_schema, _id, _deleted_at), do: nil

  # The row goes in `delete_remote/2`'s purge, under the video's lock and
  # before the provider is asked, and is checked again there. Asked first
  # too, so a refusal says why and leaves the provider alone. The purge runs
  # in this process and answers `delete_remote/2` with a boolean, so it sends
  # the reason for a refusal here.
  defp purge_video_entry(video, actor) do
    ref = make_ref()
    purge = fn -> purge_video_row(video, actor, ref) end

    if may_purge?(actor, video) do
      case Brando.Videos.Uploader.delete_remote(video, purge) do
        {:error, :not_purged} -> {:error, purge_refusal(ref)}
        {:error, reason} when reason in [:busy, :holdings_unavailable] -> {:error, reason}
        {:error, {:retry, _reason}} = error -> error
        # Deleted here; any other answer is the provider's, which is not asked again
        _deleted -> :ok
      end
    else
      {:error, :forbidden}
    end
  end

  defp purge_video_row(video, actor, ref) do
    case Repo.transaction(fn -> purge_trashed(Brando.Videos.Video, video.id, video.deleted_at, actor) end) do
      {:ok, :ok} -> true
      {:ok, {:error, reason}} -> refuse_purge(ref, reason)
      {:error, reason} -> refuse_purge(ref, reason)
    end
  end

  defp refuse_purge(ref, reason) do
    send(self(), {ref, reason})
    false
  end

  defp purge_refusal(ref) do
    receive do
      {^ref, reason} -> reason
    after
      0 -> :not_in_trash
    end
  end

  defp purge_rows_now(_schema, []), do: :ok
  defp purge_rows_now(schema, ids), do: purge_rows(schema, ids)

  # The ids of the rows deleted
  defp purge_ids(schema, ids) do
    case in_savepoint(fn -> purge_rows(schema, ids) end) do
      :ok -> ids
      {:referenced, _constraint} -> purge_one_by_one(schema, ids)
    end
  end

  defp purge_rows(schema, ids) do
    if schema.__trait__(Brando.Trait.Revisioned) do
      Enum.each(ids, &Brando.Revisions.delete_entry_revisions(schema, &1))
    end

    Brando.Notes.entries_purged(schema, ids)
    Brando.Translations.entries_deleted(schema, ids)
    before_purge(schema, ids)
    Repo.delete_all(from t in schema, where: t.id in ^ids)
  end

  # A row something still refers to (a user who created a page) is kept: each
  # row is tried on its own, and one whose delete hits a foreign key is rolled
  # back, hook and all. Its next purge tries it again.
  defp purge_one_by_one(schema, ids) do
    {deleted, constraints} = Enum.reduce(ids, {[], []}, &purge_one(schema, &1, &2))

    if constraints != [] do
      Logger.info(
        "[Brando.SoftDelete] Kept #{length(constraints)} expired #{inspect(schema)}#{environment()}, " <>
          "still referred to: #{constraints |> Enum.uniq() |> Enum.sort() |> Enum.join(", ")}"
      )
    end

    deleted
  end

  defp purge_one(schema, id, {deleted, constraints}) do
    case in_savepoint(fn -> purge_rows(schema, [id]) end) do
      :ok -> {[id | deleted], constraints}
      {:referenced, constraint} -> {deleted, [constraint | constraints]}
    end
  end

  # A foreign-key violation rolls back to the savepoint, and the transaction
  # goes on. Any other error is raised, and fails the schema's purge.
  defp in_savepoint(fun) do
    Repo.repo().query!("SAVEPOINT brando_soft_delete_purge")
    fun.()
    Repo.repo().query!("RELEASE SAVEPOINT brando_soft_delete_purge")
    :ok
  rescue
    error in Postgrex.Error ->
      case error do
        %{postgres: %{code: :foreign_key_violation} = postgres} ->
          Repo.repo().query!("ROLLBACK TO SAVEPOINT brando_soft_delete_purge")
          Repo.repo().query!("RELEASE SAVEPOINT brando_soft_delete_purge")
          {:referenced, postgres[:constraint]}

        error ->
          reraise error, __STACKTRACE__
      end
  end

  defp before_purge(_schema, []), do: :ok

  defp before_purge(schema, ids) do
    context = schema.__modules__().context

    if Code.ensure_loaded?(context) and function_exported?(context, :before_purge, 2),
      do: context.before_purge(schema, ids)
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
