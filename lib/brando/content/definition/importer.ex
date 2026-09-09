defmodule Brando.Content.Definition.Importer do
  @moduledoc false

  alias Brando.Authorization.Boundary
  alias Brando.Content.{Blocks, Module, ModuleDiff, TableTemplate}
  alias Brando.Content.Definition.{Error, Model, Params, Plan, References, Snapshot, Value}
  alias Brando.Content.Definitions
  alias Brando.Query.Mutations
  alias Brando.Repo
  alias Ecto.Changeset

  def retry_refresh(uids, actor) do
    Definitions.protect(fn ->
      Snapshot.ensure_scope!()
      ensure_actor_scope!(actor)

      changes =
        Enum.map(uids, fn uid ->
          record = Repo.get_by(Module, uid: uid) || Error.raise!(uid, "unknown module")
          authorize!(actor, :update, Module, record)
          if record.deleted_at || record.source_module_id, do: Error.raise!(uid, "expected a local active definition")
          %{uid: uid, id: record.id, kind: "module", action: :update}
        end)

      refresh(changes)
    end)
  end

  def plan(bundle, actor, opts) do
    Definitions.protect(fn ->
      Snapshot.ensure_scope!()
      ensure_actor_scope!(actor)
      creator = creator!(actor, opts)
      bindings = References.bind!(bundle, Keyword.get(opts, :references, %{}), actor)
      {plan, _records} = plan!(bundle, actor, creator, bindings)
      plan
    end)
  end

  def apply(%Plan{} = plan, actor) do
    with {:ok, result} <- Definitions.protect(fn -> apply!(plan, actor) end) do
      result
    end
  rescue
    Ecto.StaleEntryError -> {:error, "definition changed while applying; create a new plan"}
    Ecto.ConstraintError -> {:error, "a database constraint rejected the import; no definitions were committed"}
  end

  defp apply!(plan, actor) do
    if plan.scope != References.scope(), do: Error.raise!("scope", "plan belongs to another installation or environment")
    unless Plan.applicable?(plan), do: Error.raise!("plan", "resolve conflicts and migrations before applying")
    creator = creator!(actor, creator: plan.creator_id)

    result =
      Repo.transaction(fn ->
        lock!()
        References.bind!(Map.merge(plan.bundle, %{"source" => plan.scope, "references" => plan.references}), %{}, actor)
        {current, records} = plan!(plan.bundle, actor, creator, plan.references)

        unless current.fingerprint == plan.fingerprint and Plan.applicable?(current),
          do: Repo.rollback("target changed after planning; create a new plan")

        persist!(current, records, actor, creator)
      end)

    case result do
      {:ok, changes} ->
        bundle =
          plan.bundle
          |> Map.merge(%{
            "source" => plan.scope,
            "references" => plan.references,
            "baseline" => Snapshot.baselines(plan.bundle)
          })

        {:ok, %{changes: changes, refresh: refresh(changes), bundle: bundle}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp plan!(bundle, actor, creator, bindings) do
    Model.validate_graph!(bundle)
    ensure_actor_scope!(actor)

    snapshot_bindings =
      if bundle["source"] == References.scope(),
        do: Map.merge(bindings, bundle["references"] || %{}),
        else: bindings

    {snapshot, records} = Snapshot.take!(bindings: snapshot_bindings, all_tables: true)
    parents = parents(bundle["modules"])
    current_parents = parents(snapshot["modules"])
    table_ids = Map.new(records.tables, fn {uid, table} -> {uid, table.id} end)
    snapshots = Map.new(snapshot["modules"] ++ snapshot["table_templates"], &{&1["uid"], &1})

    items =
      Enum.map(bundle["table_templates"] ++ bundle["modules"], fn definition ->
        uid = definition["uid"]
        kind = definition["kind"]
        schema = if kind == "module", do: Module, else: TableTemplate
        record = if kind == "module", do: records.modules[uid], else: records.tables[uid]
        old = snapshots[uid]
        action = if record, do: :update, else: :create
        authorize!(actor, action, schema, record)
        if record && Map.get(record, :source_module_id), do: Error.raise!(uid, "shared-library overrides are unsupported")
        if record && kind == "module" && is_nil(old), do: Error.raise!(uid, "shared-library descendants are unsupported")

        if is_nil(record) and Repo.get_by(schema, uid: uid),
          do: Error.raise!(uid, "UID belongs to a deleted or unavailable definition")

        parent_id =
          with parent when not is_nil(parent) <- parents[uid],
               record when not is_nil(record) <- records.modules[parent],
               do: record.id

        changeset = Params.changeset(definition, record, bindings, creator, table_ids, parent_id)
        Model.apply_valid!(changeset, uid)

        if kind == "module" do
          Enum.each(Changeset.get_assoc(changeset, :refs), fn ref ->
            ref |> Brando.MarkdownSources.validate_placement(actor) |> Model.apply_valid!(uid <> ".refs")
          end)
        end

        validate_ref_uids!(definition, record)
        validate_template!(definition)
        digest = Value.digest(definition)
        old_digest = if old, do: Value.digest(old)
        baseline_kind = if kind == "module", do: "modules", else: "table_templates"
        baseline = get_in(bundle, ["baseline", baseline_kind, uid])
        baseline = if is_nil(record) and bundle["source"] != References.scope(), do: nil, else: baseline
        block_ids = if record && kind == "module", do: Blocks.list_block_ids_using_module(record.id), else: []

        {action, reason} =
          classify(definition, old, record, changeset, baseline, digest, old_digest, parents[uid], current_parents[uid])

        %{
          kind: kind,
          uid: uid,
          action: action,
          reason: reason,
          before: old_digest,
          after: digest,
          fields: changed_fields(old, definition),
          block_count: length(block_ids),
          entry_count: entry_count(block_ids)
        }
      end)

    scope = References.scope()

    fingerprint =
      Value.digest(%{
        "scope" => scope,
        "items" => Enum.map(items, &Map.take(&1, [:uid, :before, :after, :action])),
        "bindings" => bindings
      })

    {%Plan{
       bundle: bundle,
       items: items,
       references: bindings,
       creator_id: creator.id,
       scope: scope,
       fingerprint: fingerprint
     }, records}
  end

  defp validate_ref_uids!(%{"kind" => "table_template"}, _record), do: :ok

  defp validate_ref_uids!(definition, record) do
    Enum.each(definition["refs"], fn ref ->
      case Repo.get_by(Brando.Content.Ref, uid: ref["uid"]) do
        nil ->
          :ok

        existing ->
          unless record && existing.module_id == record.id,
            do: Error.raise!(ref["uid"], "ref UID belongs to another definition or block")
      end
    end)
  end

  defp classify(_new, nil, nil, _cs, nil, _digest, nil, _parent, _old_parent), do: {:create, nil}

  defp classify(_new, nil, nil, _cs, _baseline, _digest, nil, _parent, _old_parent),
    do: {:conflict, "the exported definition was deleted from the target"}

  defp classify(_new, _old, _record, _cs, _baseline, same, same, parent, parent), do: {:noop, nil}

  defp classify(_new, _old, _record, _cs, nil, _digest, _old_digest, _parent, _old_parent),
    do: {:conflict, "missing baseline; export the target before editing it"}

  defp classify(_new, _old, _record, _cs, baseline, _digest, old_digest, _parent, _old_parent)
       when baseline != old_digest, do: {:conflict, "target changed since export"}

  defp classify(new, old, record, cs, _baseline, _digest, _old_digest, parent, old_parent) do
    cond do
      parent != old_parent ->
        {:migration_required, "moving an existing child requires a migration"}

      new["kind"] == "table_template" and new["vars"] != old["vars"] ->
        {:migration_required, "table column changes require a migration"}

      new["kind"] == "module" and old["children"] -- new["children"] != [] ->
        {:migration_required, "removing child definitions requires a migration"}

      new["kind"] == "module" and changed_ref_identity?(old, new) ->
        {:migration_required, "changing a reference identity requires a migration"}

      new["kind"] == "module" and changed_ref_type?(old, new) ->
        {:migration_required, "changing a reference type requires a migration"}

      new["kind"] == "module" and new["table_template"] != old["table_template"] ->
        {:migration_required, "changing the table template requires a migration"}

      new["kind"] == "module" and ModuleDiff.destructive?(ModuleDiff.diff(record, cs)) ->
        {:migration_required, Enum.join(ModuleDiff.summary(ModuleDiff.diff(record, cs)), "; ")}

      true ->
        {:update, nil}
    end
  end

  defp changed_ref_identity?(old, new) do
    by_name = Map.new(old["refs"], &{&1["name"], &1["uid"]})
    Enum.any?(new["refs"], fn ref -> by_name[ref["name"]] && by_name[ref["name"]] != ref["uid"] end)
  end

  defp changed_ref_type?(old, new) do
    types = Map.new(old["refs"], &{&1["uid"], &1["data"]["type"]})
    Enum.any?(new["refs"], fn ref -> types[ref["uid"]] && types[ref["uid"]] != ref["data"]["type"] end)
  end

  defp persist!(plan, records, actor, creator) do
    definitions = Map.new(plan.bundle["modules"] ++ plan.bundle["table_templates"], &{&1["uid"], &1})
    parents = parents(plan.bundle["modules"])

    ordered =
      Enum.sort_by(plan.items, fn item ->
        {if(item.kind == "table_template", do: 0, else: 1), depth(item.uid, parents)}
      end)

    initial = %{modules: records.modules, tables: records.tables, changes: []}

    Enum.reduce(ordered, initial, fn item, state ->
      if item.action == :noop do
        state
      else
        definition = definitions[item.uid]
        kind = if item.kind == "module", do: :modules, else: :tables
        schema = if kind == :modules, do: Module, else: TableTemplate
        record = state[kind][item.uid]
        parent_id = if parent = parents[item.uid], do: state.modules[parent].id
        tables = Map.new(state.tables, fn {uid, table} -> {uid, table.id} end)
        cs = Params.changeset(definition, record, plan.references, creator, tables, parent_id)
        cs = ensure_revision(cs, kind, record)

        result =
          if item.action == :create do
            Mutations.create_with_changeset(schema, cs, actor, &{:ok, &1}, notify?: false, pubsub?: false)
          else
            Mutations.update_with_changeset(schema, cs, actor, nil, &{:ok, &1}, show_notification: false, pubsub: false)
          end

        case result do
          {:ok, saved} ->
            saved = Repo.preload(saved, if(kind == :modules, do: [:refs, :vars], else: [:vars]))
            change = %{kind: item.kind, uid: item.uid, id: saved.id, action: item.action}
            state |> put_in([kind, item.uid], saved) |> Map.update!(:changes, &(&1 ++ [change]))

          {:error, reason} ->
            Repo.rollback(%{uid: item.uid, error: reason})
        end
      end
    end).changes
  end

  defp ensure_revision(cs, :modules, record) when not is_nil(record) do
    if Changeset.changed?(cs, :version), do: cs, else: Changeset.optimistic_lock(cs, :version, &((&1 || 1) + 1))
  end

  defp ensure_revision(cs, _, _), do: cs

  defp refresh(changes) do
    changes
    |> Enum.filter(&(&1.kind == "module"))
    |> Enum.map(fn change ->
      try do
        module = Repo.get!(Module, change.id)
        Brando.Cache.Query.evict({:ok, module})
        if change.action == :update, do: Blocks.render_entries_with_module_id(module.id)
        event = if change.action == :create, do: :created, else: :updated
        Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:modules", {module, [:module, event]})
        %{uid: change.uid, status: :requested, stale_block_ids: Blocks.list_stale_block_ids(module)}
      rescue
        error -> %{uid: change.uid, status: :failed, error: Exception.message(error)}
      end
    end)
  end

  defp validate_template!(%{"kind" => "table_template"}), do: :ok

  defp validate_template!(%{"uid" => uid, "type" => "heex", "code" => code}) do
    Brando.Villain.HeexRenderer.get_or_compile!("definition_" <> uid, code)
    :ok
  rescue
    error -> Error.raise!(uid, "invalid HEEx template: #{Exception.message(error)}")
  end

  defp validate_template!(%{"uid" => uid, "code" => code}) do
    parser = Brando.config(Brando.Villain, :liquex_parser) || Brando.Villain.LiquexParser

    case Liquex.parse(code, parser) do
      {:ok, _} -> :ok
      error -> Error.raise!(uid, "invalid Liquid template: #{inspect(error)}")
    end
  end

  defp creator!(actor, opts) do
    id = if actor == :system, do: Keyword.get(opts, :creator), else: Map.get(actor, :id)
    id = if is_map(id), do: id.id, else: id
    user = if id, do: Repo.get(Brando.Users.User, id)

    if is_nil(user) or not is_nil(Map.get(user, :deleted_at)) or not user.active,
      do: Error.raise!("creator", "supply an active user; :system callers must pass creator: user_id")

    user
  end

  defp ensure_actor_scope!(actor), do: Definitions.validate_actor!(actor)

  defp authorize!(actor, action, schema, record) do
    result =
      if record,
        do: Boundary.authorize_record(actor, action, schema, record.id),
        else: Boundary.authorize(actor, action, schema)

    if result != :ok, do: Error.raise!("authorization", "forbidden")
  end

  defp parents(modules),
    do: Map.new(Enum.flat_map(modules, fn parent -> Enum.map(parent["children"], &{&1, parent["uid"]}) end))

  defp depth(uid, parents), do: if(parents[uid], do: 1 + depth(parents[uid], parents), else: 0)
  defp changed_fields(nil, definition), do: Map.keys(definition) |> Enum.sort()

  defp changed_fields(old, definition),
    do: definition |> Enum.filter(fn {k, v} -> old[k] != v end) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

  defp entry_count([]), do: 0

  defp entry_count(ids),
    do:
      ids
      |> Blocks.list_root_block_ids_by_source()
      |> Blocks.list_entry_ids_for_root_blocks_by_source()
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.sum()

  defp lock! do
    prefix = Brando.Tenant.current_prefix() || "public"

    tables =
      Enum.map_join(~w(content_modules content_table_templates content_refs content_vars), ", ", &~s("#{prefix}"."#{&1}"))

    Ecto.Adapters.SQL.query!(Repo.repo(), "LOCK TABLE " <> tables <> " IN SHARE ROW EXCLUSIVE MODE", [])
  end
end
