defmodule Brando.Content.Definitions.Release.Batches do
  @moduledoc """
  Keep or revert an apply of a release's module definitions.

  Each release apply is recorded as a `Brando.Content.DefinitionBatch`. It
  stays revertible, with no time limit, until someone who may apply release
  definitions keeps it (`keep/2`), or the next release apply confirms it.
  `revert/2` applies again what the apply replaced, as recorded in each of
  its `Brando.Content.DefinitionApply` rows' `previous`, through the same
  plan and apply as a release apply, and re-renders the entries. A
  definition edited here after the apply is left as it is and reported as a
  conflict: the edit is newer than both versions. A definition the apply
  created stays.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Definition.{Plan, References, Snapshot}
  alias Brando.Content.{DefinitionApply, DefinitionBatch, Definitions}
  alias Brando.Content.Definitions.Release
  alias Brando.Repo

  @doc "The latest release apply that is neither kept nor reverted, here, or nil."
  @spec pending() :: DefinitionBatch.t() | nil
  def pending do
    Repo.one(
      from(b in DefinitionBatch,
        where: b.source == :release and is_nil(b.confirmed_at) and is_nil(b.reverted_at),
        order_by: [desc: b.id],
        limit: 1,
        preload: [:applied_by]
      )
    )
  end

  @doc "The batch `batch_id`, or nil."
  def get(batch_id), do: Repo.one(from(b in DefinitionBatch, where: b.batch_id == ^batch_id, preload: [:applied_by]))

  @doc "The latest batch here (an apply or a revert), or nil."
  def latest,
    do:
      Repo.one(
        from(b in DefinitionBatch, order_by: [desc: b.id], limit: 1, preload: [:applied_by, :confirmed_by, :reverted_by])
      )

  @doc "The apply rows of `batch`."
  def rows(%DefinitionBatch{batch_id: batch_id}),
    do: Repo.all(from(a in DefinitionApply, where: a.batch_id == ^batch_id, order_by: a.id))

  @doc """
  Inserts the batch of an apply, in its transaction, and confirms the apply
  before it that was still waiting (`confirmed_how: :next_apply`). `items`
  are what it changed.
  """
  def insert!(attrs, user_id) do
    now = DateTime.utc_now()

    if attrs.source == :release do
      Repo.update_all(
        from(b in DefinitionBatch,
          where: b.source == :release and is_nil(b.confirmed_at) and is_nil(b.reverted_at)
        ),
        set: [confirmed_at: now, confirmed_by_id: user_id, confirmed_how: :next_apply]
      )
    end

    %DefinitionBatch{}
    |> Ecto.Changeset.change(Map.merge(attrs, %{applied_by_id: user_id, applied_at: now}))
    |> Repo.insert!()
  end

  @doc """
  Keeps `batch`: it can't be reverted any more. Takes someone who may apply
  release definitions (`Release.authorize/1`). Returns `{:ok, batch}` or
  `{:error, reason}`.
  """
  def keep(%DefinitionBatch{} = batch, user) do
    with :ok <- Release.authorize(user),
         :ok <- open(batch) do
      {1, _} =
        Repo.update_all(from(b in DefinitionBatch, where: b.id == ^batch.id and is_nil(b.confirmed_at)),
          set: [confirmed_at: DateTime.utc_now(), confirmed_by_id: user_id(user), confirmed_how: :kept]
        )

      batch = get(batch.batch_id)
      Brando.Activity.setting_changed(:updated, batch, title(batch), user, details: %{"kept" => true})
      broadcast()
      {:ok, batch}
    end
  end

  defp open(%DefinitionBatch{source: :release, confirmed_at: nil, reverted_at: nil}), do: :ok
  defp open(%DefinitionBatch{reverted_at: %DateTime{}}), do: {:error, :reverted}
  defp open(%DefinitionBatch{confirmed_at: %DateTime{}}), do: {:error, :kept}
  defp open(_batch), do: {:error, :not_revertible}

  @doc """
  What reverting `batch` would do, without doing it: `%{plan: plan, revert:
  [item], conflicts: [item], created: [uid]}`. `revert` are the plan items it
  applies again; `conflicts` those edited here since the apply (each with
  `edited`, who and when), which it leaves as they are; `created` the
  definitions the apply created, which stay.
  """
  def preview(%DefinitionBatch{} = batch, user) do
    with :ok <- Release.authorize(user),
         {:ok, actor, plan_opts} <- Release.actor(user: user_id(user)) do
      rows = rows(batch)
      restorable = Enum.filter(rows, &(&1.action in [:updated, :replaced] and is_map(&1.previous)))
      created = for row <- rows, row.action == :created, do: row.uid

      if restorable == [] do
        {:ok, %{plan: nil, revert: [], conflicts: [], created: created, actor: actor, plan_opts: plan_opts}}
      else
        bundle = bundle(restorable)
        uids = Enum.map(restorable, & &1.uid)

        with {:ok, plan} <- Definitions.plan(bundle, actor, plan_opts ++ [baseline: :database, select: uids]) do
          {revert, conflicts} = split(plan, uids)

          {:ok,
           %{
             plan: plan,
             bundle: bundle,
             revert: revert,
             conflicts: conflicts,
             created: created,
             actor: actor,
             plan_opts: plan_opts
           }}
        end
      end
    end
  end

  # The items to restore, and those edited here since the apply. A tree with
  # a conflict in it is left out whole: an apply writes whole trees.
  defp split(plan, uids) do
    items = Enum.filter(plan.items, &(&1.uid in uids))
    conflicts = Enum.filter(items, &(&1.action not in [:update, :noop]))
    blocked = MapSet.new(conflicts, &tree_root(&1.uid, plan.bundle))
    revert = Enum.filter(items, &(&1.action == :update and not MapSet.member?(blocked, tree_root(&1.uid, plan.bundle))))
    {revert, conflicts}
  end

  defp tree_root(uid, bundle) do
    parents = for module <- bundle["modules"], child <- module["children"], into: %{}, do: {child, module["uid"]}
    root(uid, parents)
  end

  defp root(uid, parents), do: if(parent = parents[uid], do: root(parent, parents), else: uid)

  @doc """
  Reverts `batch`: applies again the definitions it replaced, except those
  edited here since, and records the revert as a batch of its own. Returns
  `{:ok, %{batch: revert_batch, reverted: [item], conflicts: [item], created:
  [uid], run: run_id}}` or `{:error, reason}`. The renders it queues are
  followed with `Brando.Content.Definitions.refresh_status/1`.
  """
  def revert(%DefinitionBatch{} = batch, user) do
    with :ok <- Release.authorize(user),
         :ok <- open(batch),
         {:ok, preview} <- preview(batch, user) do
      revert_batch_id = Ecto.UUID.generate()
      uids = Enum.map(preview.revert, & &1.uid)

      {result, run} =
        Definitions.track_refresh(fn ->
          case uids do
            [] -> transaction_only(batch, preview, revert_batch_id, user)
            uids -> apply_revert(batch, preview, uids, revert_batch_id, user)
          end
        end)

      with {:ok, revert_batch} <- result do
        revert_batch = %{revert_batch | run_id: run}
        Repo.update_all(from(b in DefinitionBatch, where: b.id == ^revert_batch.id), set: [run_id: run])

        Brando.Activity.setting_changed(:created, revert_batch, title(revert_batch), user,
          details: %{"reverted" => batch.batch_id, "definitions" => length(uids)}
        )

        broadcast()

        {:ok,
         %{
           batch: revert_batch,
           reverted: preview.revert,
           conflicts: preview.conflicts,
           created: preview.created,
           run: run
         }}
      end
    end
  end

  defp apply_revert(batch, preview, uids, revert_batch_id, user) do
    opts = preview.plan_opts ++ [baseline: :database, select: uids]

    with {:ok, plan} <- Definitions.plan(preview.bundle, preview.actor, opts),
         true <- Plan.applicable?(plan) || {:error, "edited while reverting; try again"},
         {:ok, _result} <-
           Definitions.apply(plan, preview.actor,
             source: :revert,
             release: batch.release,
             action: :reverted,
             adopt: false,
             batch_id: revert_batch_id,
             in_transaction: fn current, changes -> record_revert!(batch, current, changes, revert_batch_id, user) end
           ) do
      {:ok, get(revert_batch_id)}
    end
  end

  # Nothing to apply (each definition was edited here since): the apply is
  # reverted all the same, so its banner goes
  defp transaction_only(batch, _preview, revert_batch_id, user) do
    Repo.transaction(fn -> record_revert!(batch, nil, [], revert_batch_id, user) end)
    {:ok, get(revert_batch_id)}
  end

  defp record_revert!(batch, _plan, changes, revert_batch_id, user) do
    now = DateTime.utc_now()

    {1, _} =
      Repo.update_all(
        from(b in DefinitionBatch, where: b.id == ^batch.id and is_nil(b.reverted_at) and is_nil(b.confirmed_at)),
        set: [reverted_at: now, reverted_by_id: user_id(user), revert_batch_id: revert_batch_id]
      )

    insert!(
      %{
        batch_id: revert_batch_id,
        source: :revert,
        release: batch.release,
        reverts_batch_id: batch.batch_id,
        definitions: %{"items" => Enum.map(changes, &%{"uid" => &1.uid, "kind" => &1.kind, "action" => "reverted"})}
      },
      user_id(user)
    )
  end

  # The definitions as they are here, with each one `rows` restores as it
  # was before the apply, for the trees they belong to. `previous` holds its
  # tokens as the records they name (`"image:42"`).
  defp bundle(rows) do
    {snapshot, _records} = Snapshot.take!(all_tables: true)
    previous = Map.new(rows, &{&1.uid, &1.previous})
    parents = for module <- snapshot["modules"], child <- module["children"], into: %{}, do: {child, module["uid"]}
    roots = MapSet.new(Map.keys(previous), &root(&1, parents))

    modules =
      for module <- snapshot["modules"],
          MapSet.member?(roots, root(module["uid"], parents)),
          do: Map.get(previous, module["uid"], module)

    tables = Enum.map(snapshot["table_templates"], &Map.get(previous, &1["uid"], &1))
    bundle = %{"format_version" => 1, "modules" => modules, "table_templates" => tables}

    Map.merge(bundle, %{
      "references" => references(bundle, snapshot["references"]),
      "source" => References.scope()
    })
  end

  defp references(bundle, known) do
    bundle
    |> References.declared()
    |> Map.new(fn {token, kind} ->
      case known[token] do
        %{"kind" => ^kind} = binding -> {token, binding}
        _ -> {token, %{"kind" => kind, "id" => parse_id(token, kind)}}
      end
    end)
  end

  defp parse_id(token, kind) do
    with [^kind, id | _] <- String.split(token, ":"),
         {id, ""} <- Integer.parse(id) do
      id
    else
      _ -> nil
    end
  end

  @doc """
  How `batch` stands: its renders (`Brando.Content.Definitions.refresh_status/1`)
  and the definitions edited here since it applied them (`changed_since`,
  each with the plan item's `edited`). Takes the user as `preview/2` does.
  """
  def status(%DefinitionBatch{} = batch, user) do
    renders = if batch.run_id, do: Definitions.refresh_status(batch.run_id)

    conflicts =
      case preview(batch, user) do
        {:ok, %{conflicts: conflicts}} -> conflicts
        _ -> []
      end

    %{renders: renders, changed_since: conflicts}
  end

  @doc "The batch's title in Activity: the release it applied."
  def title(%DefinitionBatch{source: :revert, release: release}), do: "Release #{release} module definitions reverted"
  def title(%DefinitionBatch{release: release}), do: "Release #{release} module definitions"

  defp broadcast do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Definitions.topic(),
      {:definitions_batch_changed, Brando.Tenant.current_prefix()}
    )
  end

  defp user_id(%{id: id}), do: id
  defp user_id(id) when is_integer(id), do: id
  defp user_id(_), do: nil
end
