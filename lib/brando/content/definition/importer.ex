defmodule Brando.Content.Definition.Importer do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.{Block, Blocks, Module, ModuleDiff, Ref, TableTemplate, Var}
  alias Brando.Content.Definition.{Baselines, Error, Model, Params, Plan, References, Snapshot, Value}
  alias Brando.Content.Definitions
  alias Brando.Query.Mutations
  alias Brando.Repo
  alias Ecto.Changeset

  def retry_refresh(uids, actor) do
    Definitions.protect(fn ->
      Snapshot.ensure_scope!()
      ensure_actor_scope!(actor)

      changes = Enum.map(uids, &refresh_change!(&1, actor))
      refresh(changes)
    end)
  end

  defp refresh_change!(uid, actor) do
    record = Repo.get_by(Module, uid: uid) || Error.raise!(uid, "unknown module")
    authorize!(actor, :update, Module, record)
    if record.deleted_at || record.source_module_id, do: Error.raise!(uid, "expected a local active definition")
    %{uid: uid, id: record.id, kind: "module", action: :update}
  end

  def plan(bundle, actor, opts) do
    Definitions.protect(fn ->
      Snapshot.ensure_scope!()
      ensure_actor_scope!(actor)
      read_only? = actor == :system and Keyword.get(opts, :creator) == :none
      creator = if read_only?, do: %Brando.Users.User{id: 0}, else: creator!(actor, opts)
      bundle = References.upgrade(bundle)
      settings = settings!(bundle, opts)
      bindings = References.bind!(bundle, supplied_references(bundle, settings, opts), actor)
      {plan, _records} = plan!(bundle, actor, creator, bindings, settings)
      if read_only?, do: %{plan | creator_id: nil}, else: plan
    end)
  end

  # Which baseline a plan compares with, which definitions it applies and
  # which never-applied ones it may replace
  defp settings!(bundle, opts) do
    mode =
      case Keyword.get(opts, :baseline, :auto) do
        :auto -> if bundle["source"] == References.scope(), do: :lockfile, else: :database
        mode when mode in [:lockfile, :database] -> mode
      end

    uids = Enum.map(bundle["modules"] ++ bundle["table_templates"], & &1["uid"])
    replace = Keyword.get(opts, :replace, [])
    discard = Keyword.get(opts, :discard, [])
    Enum.each(replace ++ discard, &(&1 in uids || Error.raise!(&1, "is not among the definitions")))
    if discard != [] and mode != :database, do: Error.raise!("discard", "needs the database's baseline")

    selection =
      case Keyword.get(opts, :select) do
        nil -> nil
        selected -> select_trees!(bundle, Enum.uniq(selected ++ replace ++ discard))
      end

    %{
      mode: mode,
      replace: MapSet.new(replace),
      discard: MapSet.new(discard),
      selection: selection
    }
  end

  # A selected module brings its whole tree (root, siblings and descendants)
  # and the table templates the tree uses: what the export selects too.
  defp select_trees!(bundle, uids) do
    modules = Map.new(bundle["modules"], &{&1["uid"], &1})
    tables = MapSet.new(bundle["table_templates"], & &1["uid"])
    parents = parents(bundle["modules"])

    uids |> Enum.flat_map(&select_tree!(&1, modules, tables, parents)) |> MapSet.new()
  end

  defp select_tree!(uid, modules, tables, parents) do
    cond do
      Map.has_key?(modules, uid) ->
        tree = uid |> root(parents) |> descendants(modules)
        tree ++ for(tree_uid <- tree, table = modules[tree_uid]["table_template"], do: table)

      MapSet.member?(tables, uid) ->
        [uid]

      true ->
        Error.raise!(uid, "is not among the definitions")
    end
  end

  defp root(uid, parents), do: if(parent = parents[uid], do: root(parent, parents), else: uid)
  defp descendants(uid, modules), do: [uid | Enum.flat_map(modules[uid]["children"], &descendants(&1, modules))]

  # Against the database's baseline, earlier applies' bindings of the bundle's
  # tokens are this environment's; a mapping passed in names new ones.
  defp supplied_references(bundle, %{mode: :database}, opts),
    do: Map.merge(Baselines.bindings(Baselines.latest(), bundle), Keyword.get(opts, :references, %{}))

  defp supplied_references(_bundle, _settings, opts), do: Keyword.get(opts, :references, %{})

  def apply(%Plan{} = plan, actor, opts \\ []) do
    with {:ok, result} <- Definitions.protect(fn -> apply!(plan, actor, opts) end) do
      result
    end
  rescue
    Ecto.StaleEntryError -> {:error, "definition changed while applying; create a new plan"}
    Ecto.ConstraintError -> {:error, "a database constraint rejected the import; no definitions were committed"}
  end

  defp apply!(plan, actor, opts) do
    if plan.scope != References.scope(), do: Error.raise!("scope", "plan belongs to another installation or environment")
    unless Plan.applicable?(plan), do: Error.raise!("plan", "resolve conflicts and migrations before applying")
    creator = creator!(actor, creator: plan.creator_id)

    settings = %{
      mode: plan.mode,
      replace: plan.replace,
      discard: plan.discard,
      selection: plan.selection
    }

    opts = Keyword.put_new_lazy(opts, :batch_id, &Ecto.UUID.generate/0)

    result =
      Repo.transaction(fn ->
        lock!()
        References.bind!(Map.merge(plan.bundle, %{"source" => plan.scope, "references" => plan.references}), %{}, actor)
        {current, records} = plan!(plan.bundle, actor, creator, plan.references, settings)

        unless current.fingerprint == plan.fingerprint and Plan.applicable?(current),
          do: Repo.rollback("target changed after planning; create a new plan")

        changes = Brando.Activity.with_batch(opts[:batch_id], fn -> persist!(current, records, actor, creator) end)
        Baselines.record!(current, changes, records.snapshots, actor, opts)
        # The caller's own records of the apply, in its transaction
        if in_transaction = opts[:in_transaction], do: in_transaction.(current, changes)
        changes
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

        prefix = Brando.Tenant.current_prefix()
        Phoenix.PubSub.broadcast(Brando.pubsub(), Definitions.topic(), {:definitions_applied, prefix})
        Brando.Repo.after_commit(fn -> Brando.Content.Definitions.ReleaseStatus.changed(prefix) end)

        {:ok, %{changes: changes, refresh: refresh(changes), bundle: bundle, batch_id: opts[:batch_id]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp plan!(bundle, actor, creator, bindings, settings) do
    Model.validate_graph!(bundle)
    ensure_actor_scope!(actor)

    latest = Baselines.latest()

    snapshot_bindings =
      if bundle["source"] == References.scope(),
        do: Map.merge(bindings, bundle["references"] || %{}),
        else: bindings

    {snapshot, records} = Snapshot.take!(bindings: snapshot_bindings, all_tables: true)

    ctx = %{
      bundle: bundle,
      actor: actor,
      creator: creator,
      bindings: bindings,
      records: records,
      mode: settings.mode,
      replace: settings.replace,
      discard: settings.discard,
      latest: latest,
      snapshot_references: snapshot["references"],
      parents: parents(bundle["modules"]),
      current_parents: parents(snapshot["modules"]),
      table_ids: Map.new(records.tables, fn {uid, table} -> {uid, table.id} end),
      snapshots: Map.new(snapshot["modules"] ++ snapshot["table_templates"], &{&1["uid"], &1})
    }

    items = Enum.map(bundle["table_templates"] ++ bundle["modules"], &plan_item!(&1, ctx))
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
       fingerprint: fingerprint,
       mode: settings.mode,
       replace: settings.replace,
       discard: settings.discard,
       selection: settings.selection,
       # How the target's records were written as tokens, generated ones too
       snapshot_bindings: snapshot["references"]
     }, Map.put(records, :snapshots, ctx.snapshots)}
  end

  defp plan_item!(definition, ctx) do
    uid = definition["uid"]
    kind = definition["kind"]
    schema = if kind == "module", do: Module, else: TableTemplate
    record = if kind == "module", do: ctx.records.modules[uid], else: ctx.records.tables[uid]
    old = ctx.snapshots[uid]
    action = if record, do: :update, else: :create
    authorize!(ctx.actor, action, schema, record)

    if validate_plan_target!(uid, kind, schema, record, old, ctx.mode),
      do: trashed_item(definition, ctx),
      else: plan_target_item!(definition, ctx, record, old)
  end

  # In the trash: nothing about the files can be checked against it until it
  # is restored, and the rest of the plan goes on
  defp trashed_item(definition, ctx) do
    %{
      kind: definition["kind"],
      uid: definition["uid"],
      action: :conflict,
      reason: "in the trash here; restore it to apply the files' version",
      state: :deleted,
      baseline: nil,
      class: nil,
      applied: applied(ctx.latest[{definition["kind"], definition["uid"]}]),
      edited: nil,
      before: nil,
      after: Baselines.digest(definition, ctx.bindings),
      fields: [],
      diff: [],
      removes: nil,
      block_count: 0,
      entry_count: 0
    }
  end

  defp plan_target_item!(definition, ctx, record, old) do
    uid = definition["uid"]
    kind = definition["kind"]
    parent_id = parent_record_id(ctx.parents[uid], ctx.records)
    changeset = Params.changeset(definition, record, ctx.bindings, ctx.creator, ctx.table_ids, parent_id)
    Model.apply_valid!(changeset, definition_subject(kind, uid))
    validate_ref_placements!(kind, changeset, uid, ctx.actor)
    validate_ref_uids!(definition, record)
    validate_template!(definition, ctx.actor)
    {digest, old_digest} = digests(ctx, definition, old)
    row = ctx.latest[{kind, uid}]
    {base, source, matches} = plan_baseline(ctx, definition, record, old, row)
    state = state(record, digest, old_digest, base, matches)
    baseline = if matches.target, do: old_digest, else: base
    block_ids = module_block_ids(kind, record)

    {action, reason} =
      action(ctx, {state, source}, fn ->
        classify(
          definition,
          old,
          record,
          changeset,
          {baseline, digest, old_digest},
          {ctx.parents[uid], ctx.current_parents[uid]}
        )
      end)

    %{
      kind: kind,
      uid: uid,
      action: action,
      reason: reason,
      state: state,
      baseline: source,
      class: diff_class(kind, record, old, changeset),
      applied: applied(row),
      edited: if(state in [:changed_in_admin, :changed_in_both], do: last_edit(kind, record, row)),
      before: old_digest,
      after: digest,
      fields: changed_fields(old, definition),
      diff: field_diff(old, definition),
      removes: removes(action, kind, record, changeset),
      block_count: length(block_ids),
      entry_count: entry_count(block_ids)
    }
  end

  defp action(%{mode: :database}, {:deleted, _source}, _classify),
    do: {:conflict, "deleted here after it was applied; a release apply that names it in replace: creates it again"}

  # The files bring what was last applied here; the admin's edit since stays,
  # and nothing is applied
  defp action(%{mode: :database}, {:changed_in_admin, :applied}, _classify), do: {:noop, nil}

  defp action(ctx, {:never_applied, _source}, classify) do
    case classify.() do
      {:conflict, _reason} -> {:conflict, never_applied_reason(ctx.mode)}
      result -> result
    end
  end

  defp action(_ctx, _state, classify), do: classify.()

  # Against the database's baseline, the files and the target are compared by
  # the records their tokens name, as apply rows record them: the target
  # names them in its own way. Against the lockfile, exactly.
  defp digests(%{mode: :database} = ctx, definition, old),
    do: {Baselines.digest(definition, ctx.bindings), old && Baselines.digest(old, ctx.snapshot_references)}

  defp digests(_ctx, definition, old), do: {Value.digest(definition), old && Value.digest(old)}

  # How the definition in the files, the one in the database and the baseline
  # relate (`Brando.Content.Definition.Watcher` shows the same states)
  defp state(nil, _digest, _old_digest, nil, _matches), do: :new
  defp state(nil, _digest, _old_digest, _base, _matches), do: :deleted
  defp state(_record, same, same, _base, _matches), do: :in_sync
  defp state(_record, _digest, _old_digest, nil, _matches), do: :never_applied
  defp state(_record, _digest, _old_digest, _base, %{target: true}), do: :changed_in_release
  defp state(_record, _digest, _old_digest, _base, %{file: true}), do: :changed_in_admin
  defp state(_record, _digest, _old_digest, _base, _matches), do: :changed_in_both

  defp never_applied_reason(:database),
    do: "never applied from files, and the database copy differs; replace it to use the files' version"

  defp never_applied_reason(:lockfile), do: "missing baseline; export the target before editing it"

  defp diff_class("module", record, old, changeset) when not is_nil(record) and not is_nil(old),
    do: ModuleDiff.classify(ModuleDiff.diff(record, changeset))

  defp diff_class(_kind, _record, _old, _changeset), do: nil

  defp applied(nil), do: nil

  defp applied(row),
    do: %{
      at: row.applied_at,
      by: row.applied_by,
      action: row.action,
      source: row.source,
      release: row.release
    }

  # Who changed the module in the admin last, after the last apply: the
  # activity log knows, and without an event there, when the row changed
  defp last_edit("module", %{id: id} = record, row) do
    since = row && row.applied_at

    query =
      from(e in Brando.Activity.Event,
        where: e.schema == ^to_string(Module) and e.entry_id == ^id,
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: 1,
        preload: [:user]
      )

    query = if since, do: from(e in query, where: e.inserted_at > ^since), else: query

    case Repo.one(query) do
      nil -> %{at: record.updated_at, by: nil}
      event -> %{at: event.inserted_at, by: event.user}
    end
  end

  defp last_edit(_kind, _record, _row), do: nil

  # Whether the definition was deleted in the target. Against the
  # database's baseline that is a conflict of its own, so one module in the
  # trash doesn't keep a release's other definitions from being planned.
  defp validate_plan_target!(uid, kind, schema, record, old, mode) do
    validate_local!(uid, kind, record, old)

    cond do
      not is_nil(record) or is_nil(Repo.get_by(schema, uid: uid)) -> false
      mode == :database -> true
      true -> Error.raise!(uid, "UID belongs to a deleted or unavailable definition")
    end
  end

  defp validate_local!(uid, kind, record, old) do
    if record && Map.get(record, :source_module_id), do: Error.raise!(uid, "shared-library overrides are unsupported")
    if record && kind == "module" && is_nil(old), do: Error.raise!(uid, "shared-library descendants are unsupported")
  end

  defp parent_record_id(parent, records) do
    with parent when not is_nil(parent) <- parent,
         record when not is_nil(record) <- records.modules[parent],
         do: record.id
  end

  defp validate_ref_placements!(kind, changeset, uid, actor) do
    if kind == "module" do
      Enum.each(Changeset.get_assoc(changeset, :refs), fn ref ->
        ref |> Brando.MarkdownSources.validate_placement(actor) |> Model.apply_valid!(definition_subject(kind, uid))
      end)
    end
  end

  defp definition_subject("table_template", uid), do: ~s(table template "#{uid}")
  defp definition_subject(_kind, uid), do: ~s(module "#{uid}")

  # The baseline a definition is compared with, where it came from, and
  # whether it equals the target and the file. Each baseline is recorded in
  # its own digest version; one that matches the target stands for the
  # target's exact digest from then on.
  #
  #   * named in `replace:` — the target as it is: the files replace it
  #   * against the database (`:database`) — the latest apply recorded here;
  #     without one, the lockfile's, but only when the target equals it
  #   * against the lockfile — the lockfile's, as recorded in development
  # The target and the files are each digested with their own bindings: a
  # recorded apply is compared by the records its tokens name
  defp plan_baseline(ctx, definition, record, old, row) do
    {base, source, {target_digest, file_digest}} = baseline_source(ctx, definition, record, old, row)

    matches = %{
      target: not is_nil(base) and not is_nil(old) and base == target_digest.(old),
      file: not is_nil(base) and base == file_digest.(definition)
    }

    {base, source, matches}
  end

  defp baseline_source(ctx, definition, record, old, row) do
    resolved = {&Baselines.digest(&1, ctx.snapshot_references), &Baselines.digest(&1, ctx.bindings)}

    cond do
      replace?(ctx, definition, old, row) ->
        {old && elem(resolved, 0).(old), :replaced, resolved}

      discard?(ctx, definition, old, row) ->
        {elem(resolved, 0).(old), :discarded, resolved}

      ctx.mode == :database and row ->
        {row.digest, :applied, resolved}

      ctx.mode == :database ->
        database_fallback(ctx, lockfile_baseline(ctx, definition, record), old)

      true ->
        base = lockfile_baseline(ctx, definition, record)
        lockfile = &Snapshot.baseline_digest(ctx.bundle, &1)
        {base, base && :lockfile, {lockfile, lockfile}}
    end
  end

  # Named to replace, and never applied here or deleted here since: a
  # conflict on a definition applied here stays one
  defp replace?(ctx, definition, old, row),
    do: MapSet.member?(ctx.replace, definition["uid"]) and (is_nil(old) or is_nil(row))

  # Named in `discard:`, applied here and edited here since: the files'
  # version replaces the edit (the apply row keeps it in `previous`). Only
  # against the database's baseline, and only for a definition still here.
  defp discard?(ctx, definition, old, row),
    do: ctx.mode == :database and MapSet.member?(ctx.discard, definition["uid"]) and not is_nil(old) and not is_nil(row)

  # Without a record here, the lockfile's baseline counts only when the
  # target equals it
  defp database_fallback(ctx, base, old) do
    digest_fun = &Snapshot.baseline_digest(ctx.bundle, &1)

    if old && base && base == digest_fun.(old),
      do: {base, :lockfile, {digest_fun, digest_fun}},
      else: {nil, nil, {digest_fun, digest_fun}}
  end

  defp lockfile_baseline(ctx, definition, record) do
    baseline_kind = if definition["kind"] == "module", do: "modules", else: "table_templates"
    baseline = get_in(ctx.bundle, ["baseline", baseline_kind, definition["uid"]])
    if is_nil(record) and ctx.bundle["source"] != References.scope(), do: nil, else: baseline
  end

  defp module_block_ids(kind, record) do
    if record && kind == "module", do: Blocks.list_block_ids_using_module(record.id, :local), else: []
  end

  defp field_diff(old, definition) do
    Enum.map(changed_fields(old, definition), fn field ->
      %{field: field, before: old && old[field], after: definition[field]}
    end)
  end

  defp validate_ref_uids!(%{"kind" => "table_template"}, _record), do: :ok

  defp validate_ref_uids!(definition, record) do
    Enum.each(definition["refs"], &validate_ref_uid!(&1, record))
  end

  defp validate_ref_uid!(ref, record) do
    case Repo.get_by(Brando.Content.Ref, uid: ref["uid"]) do
      nil ->
        :ok

      existing ->
        unless record && existing.module_id == record.id,
          do: Error.raise!(ref["uid"], "ref UID belongs to another definition or block")
    end
  end

  # `digests` is `{baseline, digest, old_digest}` and `parents` is
  # `{parent, old_parent}`, the definition's parent in the bundle and on the target.
  defp classify(_new, nil, nil, _cs, {nil, _digest, nil}, _parents), do: {:create, nil}

  defp classify(_new, nil, nil, _cs, {_baseline, _digest, nil}, _parents),
    do: {:conflict, "the exported definition was deleted from the target"}

  defp classify(_new, _old, _record, _cs, {_baseline, same, same}, {parent, parent}), do: {:noop, nil}

  defp classify(_new, _old, _record, _cs, {nil, _digest, _old_digest}, _parents),
    do: {:conflict, "missing baseline; export the target before editing it"}

  defp classify(_new, _old, _record, _cs, {baseline, _digest, old_digest}, _parents)
       when baseline != old_digest,
       do: {:conflict, "target changed since export"}

  defp classify(new, old, record, cs, _digests, {parent, old_parent}) do
    cond do
      parent != old_parent ->
        {:migration_required, "moving an existing child requires a migration"}

      new["kind"] == "table_template" and new["vars"] != old["vars"] ->
        {:migration_required, "table column changes require a migration"}

      new["kind"] == "module" ->
        classify_module_update(new, old, record, cs)

      true ->
        {:update, nil}
    end
  end

  defp classify_module_update(new, old, record, cs) do
    diff = ModuleDiff.diff(record, cs)

    cond do
      old["children"] -- new["children"] != [] ->
        {:migration_required, "removing child definitions requires a migration"}

      changed_ref_identity?(old, new) ->
        {:migration_required, "changing a reference identity requires a migration"}

      changed_ref_type?(old, new) ->
        {:migration_required, "changing a reference type requires a migration"}

      new["table_template"] != old["table_template"] ->
        {:migration_required, "changing the table template requires a migration"}

      reinterprets?(diff) ->
        {:migration_required, Enum.join(ModuleDiff.summary(%{diff | removed_refs: [], removed_vars: []}), "; ")}

      reason = returning_over_leftovers(record, cs, diff) ->
        {:migration_required, reason}

      true ->
        {:update, nil}
    end
  end

  # A removed ref or var is an update: the blocks keep what they hold in it
  # as a leftover until it is resolved, as after the same save in the admin.
  # A retype or a contract change makes a sync reinterpret what blocks hold.
  defp reinterprets?(diff),
    do: diff.retyped_refs != [] or diff.retyped_vars != [] or diff.contract_changes != []

  # A var defined again under a key its blocks still hold a leftover of
  # another type for: a sync would copy the new type onto the stored value
  # (`Blocks.reapply_vars/3`)
  defp returning_over_leftovers(_record, _cs, %{added_vars: []}), do: nil

  defp returning_over_leftovers(record, cs, diff) do
    types = cs |> Changeset.apply_changes() |> Map.get(:vars) |> Map.new(&{&1.key, &1.type})

    from(v in Var,
      join: b in Block,
      on: b.id == v.block_id,
      where: b.module_id == ^record.id and b.module_origin == :local and v.key in ^diff.added_vars,
      order_by: [v.key, b.id],
      select: {v.key, v.type, b.id}
    )
    |> Repo.all()
    |> Enum.reject(fn {key, type, _block_id} -> type == types[key] end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 2))
    |> Enum.map(fn {key, block_ids} ->
      ~s(var "#{key}" returns as #{types[key]} while blocks #{Enum.map_join(block_ids, ", ", &"##{&1}")} ) <>
        "hold a leftover of another type; resolve it first"
    end)
    |> case do
      [] -> nil
      reasons -> Enum.join(reasons, "; ")
    end
  end

  # What an update removes, the keys of it blocks hold (`held`), and the
  # blocks that hold one and keep it as a leftover (`Brando.Content.StaleBlocks`)
  defp removes(:update, "module", record, cs) do
    diff = ModuleDiff.diff(record, cs)
    keys = Enum.map(diff.removed_refs, &{:ref, &1}) ++ Enum.map(diff.removed_vars, &{:var, &1})

    if keys != [] do
      holders = holders(record, diff)
      held = holders |> Enum.map(&elem(&1, 0)) |> MapSet.new()
      blocks = holders |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

      %{
        keys: keys,
        held: Enum.filter(keys, &MapSet.member?(held, &1)),
        blocks: length(blocks),
        entries: entry_count(blocks)
      }
    end
  end

  defp removes(_action, _kind, _record, _cs), do: nil

  # `{{kind, key}, block_id}` for each removed key a block of the module
  # holds. The module is in this database: a block of a shared library
  # module with the same id is not one of its blocks.
  defp holders(record, diff) do
    refs =
      from(r in Ref,
        join: b in Block,
        on: b.id == r.block_id,
        where: b.module_id == ^record.id and b.module_origin == :local and r.name in ^diff.removed_refs,
        select: {"ref", r.name, b.id}
      )

    from(v in Var,
      join: b in Block,
      on: b.id == v.block_id,
      where: b.module_id == ^record.id and b.module_origin == :local and v.key in ^diff.removed_vars,
      select: {"var", v.key, b.id},
      union: ^refs
    )
    |> Repo.all()
    |> Enum.map(fn {kind, key, block_id} -> {{if(kind == "ref", do: :ref, else: :var), key}, block_id} end)
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
    ctx = %{definitions: definitions, parents: parents, references: plan.references, actor: actor, creator: creator}

    Enum.reduce(ordered, initial, fn item, state ->
      if item.action == :noop or not Plan.selected?(plan, item), do: state, else: persist_item!(item, state, ctx)
    end).changes
  end

  defp persist_item!(item, state, ctx) do
    definition = ctx.definitions[item.uid]
    kind = if item.kind == "module", do: :modules, else: :tables
    schema = if kind == :modules, do: Module, else: TableTemplate
    record = state[kind][item.uid]
    parent_id = if parent = ctx.parents[item.uid], do: state.modules[parent].id
    tables = Map.new(state.tables, fn {uid, table} -> {uid, table.id} end)
    cs = Params.changeset(definition, record, ctx.references, ctx.creator, tables, parent_id)
    cs = ensure_revision(cs, kind, record)

    case save_definition(item.action, schema, cs, ctx.actor) do
      {:ok, saved} ->
        saved = Repo.preload(saved, if(kind == :modules, do: [:refs, :vars], else: [:vars]))
        change = %{kind: item.kind, uid: item.uid, id: saved.id, action: item.action}
        state |> put_in([kind, item.uid], saved) |> Map.update!(:changes, &(&1 ++ [change]))

      {:error, reason} ->
        Repo.rollback(%{uid: item.uid, error: reason})
    end
  end

  defp save_definition(action, schema, cs, actor) do
    if action == :create do
      Mutations.create_with_changeset(schema, cs, actor, &{:ok, &1}, notify?: false, pubsub?: false)
    else
      Mutations.update_with_changeset(schema, cs, actor, nil, &{:ok, &1}, show_notification: false, pubsub: false)
    end
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

  defp validate_template!(%{"kind" => "table_template"}, _actor), do: :ok

  # Compiling runs the template's code, unquote fragments at once: only a
  # superuser's, read now, in both authorization modes, even for a plan that
  # saves nothing.
  defp validate_template!(%{"uid" => uid, "type" => "heex", "code" => code}, actor) do
    if not Boundary.superuser?(actor), do: Error.raise!("authorization", "forbidden")
    compile_template!(uid, code)
  end

  defp validate_template!(%{"uid" => uid, "code" => code}, _actor) do
    parser = Brando.config(Brando.Villain, :liquex_parser) || Brando.Villain.LiquexParser

    case Liquex.parse(code, parser) do
      {:ok, _} -> :ok
      error -> Error.raise!(uid, "invalid Liquid template: #{inspect(error)}")
    end
  end

  defp compile_template!(uid, code) do
    Brando.Villain.HeexRenderer.get_or_compile!("definition_" <> uid, code)
    :ok
  rescue
    error -> Error.raise!(uid, "invalid HEEx template: #{Exception.message(error)}")
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
