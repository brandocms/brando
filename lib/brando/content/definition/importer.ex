defmodule Brando.Content.Definition.Importer do
  @moduledoc false

  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Content.{Block, Blocks, Container, Module, ModuleDiff, Palette, Ref, Var}
  alias Brando.Content.Definition.{Baselines, Drops, Error, Model, Params, Plan, References, Renames, Snapshot, Value}
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

  # A module, a palette or a container: whichever has the uid here, an
  # active one before one in the trash
  defp refresh_change!(uid, actor) do
    {kind, record} =
      Enum.find(Map.get(Snapshot.stored([uid]), uid, []), fn {kind, _record} -> kind != "table_template" end) ||
        Error.raise!(uid, "unknown definition")

    authorize!(actor, :update, Model.schema(kind), record)
    if record.deleted_at || source_id(record), do: Error.raise!(uid, "expected a local active definition")
    %{uid: uid, id: record.id, kind: kind, action: :update}
  end

  # The shared-library entry a local override is of, or nil
  defp source_id(record),
    do: Map.get(record, :source_module_id) || Map.get(record, :source_palette_id) || Map.get(record, :source_container_id)

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

    bundle = Model.with_kinds(bundle)
    uids = Enum.map(Model.definitions(bundle), & &1["uid"])
    replace = Keyword.get(opts, :replace, [])
    discard = Keyword.get(opts, :discard, [])
    Enum.each(replace ++ discard, &(&1 in uids || Error.raise!(&1, "is not among the definitions")))
    if discard != [] and mode != :database, do: Error.raise!("discard", "needs the database's baseline")

    selection =
      case Keyword.get(opts, :select) do
        nil ->
          nil

        selected ->
          (selected ++ replace ++ discard)
          |> Enum.uniq()
          |> Enum.flat_map(selection_expander(bundle))
          |> MapSet.new()
      end

    %{
      mode: mode,
      replace: MapSet.new(replace),
      discard: MapSet.new(discard),
      selection: selection,
      catch_up: Keyword.get(opts, :catch_up, false)
    }
  end

  # A selected module brings its whole tree (root, siblings and descendants),
  # the table templates the tree uses and the palettes their vars name; a
  # container brings its palette: what the export selects too. Each is in
  # the bundle, or here.
  @doc false
  def selection_expander(bundle) do
    modules = Map.new(bundle["modules"], &{&1["uid"], &1})
    containers = Map.new(bundle["containers"], &{&1["uid"], &1})
    others = MapSet.new(bundle["table_templates"] ++ bundle["palettes"], & &1["uid"])
    palettes = MapSet.new(bundle["palettes"], & &1["uid"])
    parents = parents(bundle["modules"])
    lookup = %{modules: modules, containers: containers, others: others, palettes: palettes, parents: parents}

    &select_tree!(&1, bundle, lookup)
  end

  defp select_tree!(uid, bundle, lookup) do
    cond do
      Map.has_key?(lookup.modules, uid) ->
        tree = uid |> root(lookup.parents) |> descendants(lookup.modules)
        tables = for tree_uid <- tree, table = lookup.modules[tree_uid]["table_template"], do: table
        tree ++ tables ++ Enum.filter(palette_tokens(bundle, tree ++ tables), &MapSet.member?(lookup.palettes, &1))

      Map.has_key?(lookup.containers, uid) ->
        palette = lookup.containers[uid]["palette"]
        [uid | if(MapSet.member?(lookup.palettes, palette), do: [palette], else: [])]

      MapSet.member?(lookup.others, uid) ->
        [uid]

      true ->
        Error.raise!(uid, "is not among the definitions")
    end
  end

  # The palettes the vars of the modules and table templates `uids` name by uid
  defp palette_tokens(bundle, uids) do
    for definition <- bundle["modules"] ++ bundle["table_templates"],
        definition["uid"] in uids,
        var <- definition["vars"],
        token = var["assets"]["palette"],
        binding = get_in(bundle, ["references", token]) || %{},
        not Map.has_key?(binding, "id"),
        do: binding["uid"] || token
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
    Ecto.StaleEntryError ->
      {:error, "definition changed while applying; create a new plan"}

    Ecto.ConstraintError ->
      {:error, "a database constraint rejected the import; no definitions were committed"}

    # An editor's save took a block the apply moves values in, and Postgres
    # aborted the apply to break the wait
    error in Postgrex.Error ->
      if error.postgres[:code] in [:deadlock_detected, :serialization_failure],
        do: {:error, gettext("An editor saved the same blocks at the same moment, and nothing was applied. Try again.")},
        else: reraise(error, __STACKTRACE__)
  end

  defp apply!(plan, actor, opts) do
    if plan.scope != References.scope(), do: Error.raise!("scope", "plan belongs to another installation or environment")
    unless Plan.applicable?(plan), do: Error.raise!("plan", "resolve conflicts and migrations before applying")
    creator = creator!(actor, creator: plan.creator_id)

    settings = %{
      mode: plan.mode,
      replace: plan.replace,
      discard: plan.discard,
      selection: plan.selection,
      catch_up: plan.catch_up
    }

    opts = Keyword.put_new_lazy(opts, :batch_id, &Ecto.UUID.generate/0)

    result =
      Repo.transaction(fn ->
        lock!()
        References.bind!(Map.merge(plan.bundle, %{"source" => plan.scope, "references" => plan.references}), %{}, actor)
        {current, records} = plan!(plan.bundle, actor, creator, plan.references, settings)

        check_moves!(plan, current)

        unless current.fingerprint == plan.fingerprint and Plan.applicable?(current),
          do: Repo.rollback("target changed after planning; create a new plan")

        # Planned with the definitions as they are here, before they change
        drops = if digest = opts[:drop], do: Drops.planned!(current, digest)

        {changes, current, dropped} =
          Brando.Activity.with_batch(opts[:batch_id], fn ->
            changes = persist!(current, records, actor, creator)
            current = move!(current, records, changes, creator, opts)
            {changes, current, Drops.drop!(drops, changes, creator, opts)}
          end)

        Baselines.record!(current, changes, records.snapshots, actor, opts)
        # The caller's own records of the apply, in its transaction
        if in_transaction = opts[:in_transaction], do: in_transaction.(current, changes)
        {changes, renamed(current, creator), dropped}
      end)

    case result do
      {:ok, {changes, renamed, dropped}} ->
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

        {:ok,
         %{
           changes: changes,
           refresh: refresh(changes),
           bundle: bundle,
           batch_id: opts[:batch_id],
           renamed: renamed,
           dropped: dropped
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp plan!(bundle, actor, creator, bindings, settings) do
    bundle = Model.with_kinds(bundle)
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
      # Whose entries a refusal names: the person a system plan is for
      viewer: if(actor == :system and creator.id != 0, do: creator, else: actor),
      bindings: bindings,
      records: records,
      mode: settings.mode,
      replace: settings.replace,
      discard: settings.discard,
      catch_up: settings.catch_up,
      latest: latest,
      snapshot_references: snapshot["references"],
      parents: parents(bundle["modules"]),
      current_parents: parents(snapshot["modules"]),
      table_ids: Map.new(records.tables, fn {uid, table} -> {uid, table.id} end),
      palettes: MapSet.new(bundle["palettes"], & &1["uid"]),
      stored: bundle |> Model.definitions() |> Enum.map(& &1["uid"]) |> Snapshot.stored(),
      snapshots: Map.new(Model.definitions(snapshot), &{{&1["kind"], &1["uid"]}, &1})
    }

    items =
      bundle
      |> Model.definitions()
      |> Enum.map(&plan_item!(&1, ctx))
      |> limit_moves(settings.selection)
      |> Enum.map(&refuse_moves/1)

    scope = References.scope()

    # The renames are no part of a definition's digest: a changed one
    # changes the plan all the same
    fingerprint =
      %{
        "scope" => scope,
        "items" => Enum.map(items, &Map.take(&1, [:uid, :before, :after, :action])),
        "bindings" => bindings
      }
      |> Map.merge(Map.take(bundle, ["renames"]))
      |> Value.digest()

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
       catch_up: settings.catch_up,
       # How the target's records were written as tokens, generated ones too
       snapshot_bindings: snapshot["references"]
     }, Map.put(records, :snapshots, ctx.snapshots)}
  end

  defp plan_item!(definition, ctx) do
    uid = definition["uid"]
    kind = definition["kind"]
    schema = Model.schema(kind)
    record = Snapshot.record(ctx.records, kind, uid)
    old = ctx.snapshots[{kind, uid}]
    action = if record, do: :update, else: :create
    validate_kind_here!(definition, ctx.stored)
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
      moves: nil,
      remaps: [],
      unrevertible: nil,
      block_count: 0,
      entry_count: 0
    }
  end

  defp plan_target_item!(definition, ctx, record, old) do
    uid = definition["uid"]
    kind = definition["kind"]
    parent_id = parent_record_id(ctx.parents[uid], ctx.records)
    palette = validate_palette_reference!(definition, ctx)
    changeset = Params.changeset(definition, record, ctx.bindings, ctx.creator, ctx.table_ids, parent_id)
    Model.apply_valid!(changeset, Model.subject(kind, uid))
    validate_ref_placements!(kind, changeset, uid, ctx.actor)
    validate_ref_uids!(definition, record)
    validate_template!(definition, ctx.actor)
    {digest, old_digest} = digests(ctx, definition, old)
    row = ctx.latest[{kind, uid}]
    {base, source, matches} = plan_baseline(ctx, definition, record, old, row)
    state = state(record, digest, old_digest, base, matches)
    baseline = if matches.target, do: old_digest, else: base
    block_ids = block_ids(kind, record)

    {{action, reason}, moves, remaps} =
      case palette do
        {:in_trash, palette} ->
          {{:conflict, ~s(palette "#{palette}" is in the trash here; restore it to apply the files' version)}, nil, []}

        :ok ->
          ctx
          |> action({state, source}, fn ->
            classify(
              definition,
              old,
              record,
              changeset,
              {baseline, digest, old_digest},
              {ctx.parents[uid], ctx.current_parents[uid]}
            )
          end)
          |> moves(definition, record, changeset, ctx)
      end

    %{
      kind: kind,
      uid: uid,
      action: action,
      reason: reason || unavailable_palette_reason(definition, record),
      state: state,
      baseline: source,
      class: diff_class(kind, record, old, changeset),
      applied: applied(row),
      edited: if(state in [:changed_in_admin, :changed_in_both], do: last_edit(kind, record, row)),
      before: old_digest,
      after: digest,
      fields: changed_fields(old, definition),
      diff: field_diff(old, definition),
      removes: removes(action, kind, record, {changeset, old, definition}, block_ids, moves),
      moves: moves,
      remaps: remaps,
      unrevertible: unrevertible(action, definition, old, record, changeset),
      block_count: length(block_ids),
      entry_count: entry_count(block_ids)
    }
  end

  # The values an update of a module moves under its declared renames
  # (`Renames`), and the renames it leaves to a resolve. A move refused in
  # any block makes the update need a migration once the selection's moves
  # are counted together (`refuse_moves/1`). A conflict gets only the moves
  # an apply of the files' version makes, for the review to preview.
  defp moves({:update, _reason} = action, %{"kind" => "module", "uid" => uid}, record, changeset, ctx) do
    case Renames.declared(ctx.bundle, uid) do
      [] ->
        {action, nil, []}

      renames ->
        module = Changeset.apply_changes(changeset)
        {active, rest} = Renames.split(renames, ModuleDiff.diff(record, changeset))
        moves = if active != [], do: Renames.plan(record, module, active, ctx.viewer)
        {action, moves, Renames.remaps(record, module, rest)}
    end
  end

  defp moves({:conflict, _reason} = action, %{"kind" => "module", "uid" => uid}, record, changeset, ctx)
       when not is_nil(record) do
    {active, _rest} = ctx.bundle |> Renames.declared(uid) |> Renames.split(ModuleDiff.diff(record, changeset))
    moves = if active != [], do: Renames.plan(record, Changeset.apply_changes(changeset), active, ctx.viewer)
    {action, moves, []}
  end

  # Applied already: blocks may still hold the old keys the files rename,
  # left for the resolve command by an apply over the limit
  defp moves({:noop, _reason} = action, %{"kind" => "module", "uid" => uid}, record, _changeset, ctx)
       when not is_nil(record),
       do: {action, nil, Renames.left(record, Renames.declared(ctx.bundle, uid))}

  defp moves(action, _definition, _record, _changeset, _ctx), do: {action, nil, []}

  # A move the review saw that is refused now, as the apply plans again
  # under its lock: the blocks changed in between
  defp check_moves!(reviewed, current) do
    planned = Map.new(reviewed.items, &{&1.uid, &1.action})

    refused =
      for item <- current.items,
          planned[item.uid] == :update,
          %{refused: [_ | _] = refused} <- [item.moves],
          reason <- refused,
          do: reason

    if refused != [], do: Repo.rollback(Renames.changed_since_review(refused))
  end

  # The selected updates' moves together, refused ones too: when they are
  # more than one apply moves (`Renames.over_limit/1`), the apply moves none
  # of them (`Renames.leave/1`), and only what the resolve command can't
  # move either stays refused. With nothing selected (a review of a whole
  # release, an import) each module is judged on its own; `Renames.move!/3`
  # decides what one apply then moves together.
  defp limit_moves(items, nil), do: items

  defp limit_moves(items, selection) do
    moving =
      for %{action: :update, moves: %{} = moves} = item <- items,
          MapSet.member?(selection, item.uid),
          do: {item.uid, moves}

    if Renames.over_limit(Enum.map(moving, &elem(&1, 1))) do
      uids = Map.new(moving)
      Enum.map(items, &if(uids[&1.uid], do: %{&1 | moves: Renames.leave(&1.moves)}, else: &1))
    else
      items
    end
  end

  # An update whose moves are refused needs a migration, and leaves nothing
  defp refuse_moves(%{action: :update, moves: %{refused: [_ | _] = refused}} = item),
    do: %{item | action: :migration_required, reason: Enum.join(refused, "; "), removes: nil}

  defp refuse_moves(item), do: item

  # The values the selected module updates move, as the person who applies:
  # `plan` with each item's moves as the apply made them under its lock
  defp move!(plan, records, changes, person, opts) do
    saved = Map.new(changes, &{{&1.kind, &1.uid}, &1.id})

    moves =
      for item <- plan.items,
          item.kind == "module" and item.action == :update and Plan.selected?(plan, item),
          %{renames: renames} <- [item.moves],
          id = saved[{"module", item.uid}] do
        %{
          record: records.modules[item.uid],
          module: Repo.preload(Repo.get!(Module, id), [:refs, :vars]),
          renames: Enum.map(renames, &Map.take(&1, [:kind, :from, :to]))
        }
      end

    made = Renames.move!(moves, person, release: opts[:release])
    %{plan | items: Enum.map(plan.items, &if(moves = made[&1.uid], do: %{&1 | moves: moves}, else: &1))}
  end

  # What the apply did with each module's renames that blocks hold a value
  # of: `%{uid, renames, left?, text}`, `text` the line that says what it
  # left and the command that moves it
  defp renamed(plan, person) do
    for %{action: :update, moves: %{renames: renames, left?: left?}, uid: uid} = item <- plan.items,
        Plan.selected?(plan, item),
        held = Enum.filter(renames, &(&1.blocks > 0)),
        held != [] do
      %{uid: uid, renames: held, left?: left?, text: if(left?, do: Renames.left_text(uid, held, person))}
    end
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

  # Who changed the definition in the admin last, after the last apply: the
  # activity log knows, and without an event there, when the row changed
  defp last_edit(kind, %{id: id} = record, row) when kind in ~w(module palette container) do
    since = row && row.applied_at

    query =
      from(e in Brando.Activity.Event,
        where: e.schema == ^to_string(Model.schema(kind)) and e.entry_id == ^id,
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
    if record && source_id(record), do: Error.raise!(uid, "shared-library overrides are unsupported")
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
        ref |> Brando.MarkdownSources.validate_placement(actor) |> Model.apply_valid!(Model.subject(kind, uid))
      end)
    end
  end

  # UIDs are not shared between kinds: one a definition of another kind has
  # here, in the trash too, is refused, so the two never meet in a
  # selection, an apply, a revert or a restore
  defp validate_kind_here!(%{"kind" => kind, "uid" => uid}, stored) do
    case Enum.find(Map.get(stored, uid, []), fn {other, _record} -> other != kind end) do
      nil ->
        :ok

      {other, _record} ->
        Error.raise!(Model.subject(kind, uid), "the uid belongs to a #{String.replace(other, "_", " ")} here")
    end
  end

  # A container's palette is in the files, or here and readable by the
  # actor; one in the trash is neither. Against the database's baseline (a
  # release, a revert), one in the trash makes the container a conflict, as
  # a definition in the trash is one, and the rest of the plan goes on.
  defp validate_palette_reference!(%{"kind" => "container", "palette" => palette, "uid" => uid}, ctx)
       when is_binary(palette) do
    cond do
      MapSet.member?(ctx.palettes, palette) ->
        :ok

      id = References.palette_id(palette) ->
        if Boundary.authorize_record(ctx.actor, :read, Palette, id) != :ok,
          do: Error.raise!(Model.subject("container", uid), ~s(palette "#{palette}": forbidden))

        :ok

      ctx.mode == :database and Repo.get_by(Palette, uid: palette) ->
        {:in_trash, palette}

      true ->
        Error.raise!(Model.subject("container", uid), ~s(palette "#{palette}" is neither in the files nor here))
    end
  end

  defp validate_palette_reference!(_definition, _ctx), do: :ok

  defp unavailable_palette_reason(%{"kind" => "container", "palette" => nil}, %Container{palette_id: id}) do
    if palette = References.unavailable_palette(id),
      do: ~s(default palette "#{palette.name}" is unavailable here; the import keeps the link)
  end

  defp unavailable_palette_reason(_definition, _record), do: nil

  # The baseline a definition is compared with, where it came from, and
  # whether it equals the target and the file. Each baseline is recorded in
  # its own digest version; one that matches the target stands for the
  # target's exact digest from then on.
  #
  #   * named in `replace:` — the target as it is: the files replace it
  #   * against the database (`:database`) — the latest apply recorded here;
  #     without one, the lockfile's, but only when the target equals it
  #   * against the lockfile — the lockfile's, as recorded in development;
  #     with `catch_up`, when the target no longer equals it but equals the
  #     latest apply recorded here, that apply's (the lockfile didn't advance
  #     after it: its write failed). An admin edit since that apply matches
  #     neither.
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

        if ctx.catch_up and behind_last_apply?(base, lockfile, old, row, elem(resolved, 0)),
          do: {row.digest, :applied, resolved},
          else: {base, base && :lockfile, {lockfile, lockfile}}
    end
  end

  defp behind_last_apply?(base, lockfile, old, row, target_digest),
    do:
      not is_nil(old) and not is_nil(row) and (is_nil(base) or base != lockfile.(old)) and
        row.digest == target_digest.(old)

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
    baseline = get_in(ctx.bundle, ["baseline", Model.bundle_key(definition["kind"]), definition["uid"]])
    if is_nil(record) and ctx.bundle["source"] != References.scope(), do: nil, else: baseline
  end

  defp block_ids(_kind, nil), do: []
  defp block_ids("module", record), do: Blocks.list_block_ids_using_module(record.id, :local)
  defp block_ids("palette", record), do: Blocks.list_block_ids_using_palette(record.id, :local)
  defp block_ids("container", record), do: Blocks.list_block_ids_using_container(record.id, :local)
  defp block_ids(_kind, _record), do: []

  defp field_diff(old, definition) do
    Enum.map(changed_fields(old, definition), fn field ->
      %{field: field, before: old && old[field], after: definition[field]}
    end)
  end

  defp validate_ref_uids!(%{"kind" => "module"} = definition, record) do
    Enum.each(definition["refs"], &validate_ref_uid!(&1, record))
  end

  defp validate_ref_uids!(_definition, _record), do: :ok

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
        classify_module_update(new, old, record, Changeset.apply_changes(cs))

      true ->
        {:update, nil}
    end
  end

  # `record` as it is here, `module` as the update leaves it
  defp classify_module_update(new, old, record, module) do
    diff = ModuleDiff.diff(record, module)

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

      reason = returning_over_leftovers(record, module, diff) ->
        {:migration_required, reason}

      true ->
        {:update, nil}
    end
  end

  # Why a revert couldn't apply the definition here again over an update of
  # a module, the day it is applied: the revert plans the module's previous
  # version over the one the update leaves (`Release.Batches`), and needs a
  # migration where this says so. Nil when it could, and for anything else.
  defp unrevertible(:update, %{"kind" => "module"} = definition, old, record, changeset) do
    case classify_module_update(old, definition, Changeset.apply_changes(changeset), record) do
      {:update, nil} -> nil
      {:migration_required, reason} -> reason
    end
  end

  defp unrevertible(_action, _definition, _old, _record, _changeset), do: nil

  # A removed ref or var is an update: the blocks keep what they hold in it
  # as a leftover until it is resolved, as after the same save in the admin.
  # A retype or a contract change makes a sync reinterpret what blocks hold.
  defp reinterprets?(diff),
    do: diff.retyped_refs != [] or diff.retyped_vars != [] or diff.contract_changes != []

  # A ref or var defined again under a name its blocks still hold a
  # leftover of another type for: a sync would copy the new type onto the
  # stored value (`Blocks.reapply_vars/3`), or pass a ref of another type
  # through and never add the new one (`Blocks.sync_module/2`)
  defp returning_over_leftovers(_record, _module, %{added_vars: [], added_refs: []}), do: nil

  defp returning_over_leftovers(record, module, diff) do
    var_types = Map.new(module.vars, &{&1.key, &1.type})
    ref_types = Map.new(module.refs, &{&1.name, &1.data.__struct__})

    vars =
      from(v in Var,
        join: b in Block,
        on: b.id == v.block_id,
        where: b.module_id == ^record.id and b.module_origin == :local and v.key in ^diff.added_vars,
        order_by: [v.key, b.id],
        select: {v.key, v.type, b.id}
      )
      |> Repo.all()
      |> Enum.reject(fn {key, type, _block_id} -> type == var_types[key] end)
      |> Enum.map(fn {key, _type, block_id} -> {{:var, key, var_types[key]}, block_id} end)

    refs =
      from(r in Ref,
        join: b in Block,
        on: b.id == r.block_id,
        where: b.module_id == ^record.id and b.module_origin == :local and r.name in ^diff.added_refs,
        order_by: [r.name, b.id]
      )
      |> Repo.all()
      |> Enum.reject(&Brando.Villain.Blocks.ref_types_compatible?(ref_types[&1.name], &1.data && &1.data.__struct__))
      |> Enum.map(&{{:ref, &1.name, ref_type_name(ref_types[&1.name])}, &1.block_id})

    (vars ++ refs)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map(fn {{kind, key, type}, block_ids} ->
      ~s(#{kind} "#{key}" returns as #{type} while blocks #{Enum.map_join(Enum.uniq(block_ids), ", ", &"##{&1}")} ) <>
        "hold a leftover of another type; resolve it first"
    end)
    |> case do
      [] -> nil
      reasons -> Enum.join(reasons, "; ")
    end
  end

  defp ref_type_name(struct),
    do: Enum.find_value(Brando.Villain.Blocks.list_blocks(), fn {name, mod} -> mod == struct && to_string(name) end)

  # What an update removes, the keys of it blocks hold (`held`), and the
  # blocks that hold one and keep it as a leftover (`Brando.Content.StaleBlocks`).
  # A palette's colours: the CSS that reads a removed one is the author's, and
  # the blocks that use the palette are counted.
  defp removes(:update, "palette", _record, {_cs, old, new}, block_ids, _moves) do
    keys = Enum.map(old["colors"], & &1["key"]) -- Enum.map(new["colors"], & &1["key"])

    if keys != [],
      do: %{keys: Enum.map(keys, &{:color, &1}), blocks: length(block_ids), entries: entry_count(block_ids)}
  end

  # What a rename moves is not left over
  defp removes(:update, "module", record, {cs, _old, _new}, _block_ids, moves) do
    diff = ModuleDiff.diff(record, cs)
    moved = if moves, do: Enum.map(moves.renames, &{&1.kind, &1.from}), else: []
    diff = %{diff | removed_refs: diff.removed_refs -- moved_keys(moved, :ref)}
    diff = %{diff | removed_vars: diff.removed_vars -- moved_keys(moved, :var)}
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

  defp removes(_action, _kind, _record, _changes, _block_ids, _moves), do: nil

  defp moved_keys(moved, kind), do: for({^kind, key} <- moved, do: key)

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

  # Palettes, containers, table templates, then modules, parents first
  defp persist!(plan, records, actor, creator) do
    definitions = Map.new(Model.definitions(plan.bundle), &{&1["uid"], &1})
    parents = parents(plan.bundle["modules"])
    order = Model.kinds()

    ordered =
      Enum.sort_by(plan.items, fn item ->
        {Enum.find_index(order, &(&1 == item.kind)), depth(item.uid, parents)}
      end)

    initial = records |> Map.take(~w(modules tables palettes containers)a) |> Map.put(:changes, [])
    ctx = %{definitions: definitions, parents: parents, references: plan.references, actor: actor, creator: creator}

    Enum.reduce(ordered, initial, fn item, state ->
      if item.action == :noop or not Plan.selected?(plan, item), do: state, else: persist_item!(item, state, ctx)
    end).changes
  end

  defp persist_item!(item, state, ctx) do
    definition = ctx.definitions[item.uid]
    kind = Snapshot.records_key(item.kind)
    schema = Model.schema(item.kind)
    record = state[kind][item.uid]
    parent_id = if parent = ctx.parents[item.uid], do: state.modules[parent].id
    tables = Map.new(state.tables, fn {uid, table} -> {uid, table.id} end)
    cs = Params.changeset(definition, record, ctx.references, ctx.creator, tables, parent_id)
    cs = ensure_revision(cs, kind, record)

    case save_definition(item.action, schema, cs, ctx.actor) do
      {:ok, saved} ->
        saved = Repo.preload(saved, preloads(kind))
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

  defp preloads(:modules), do: [:refs, :vars]
  defp preloads(:tables), do: [:vars]
  defp preloads(_kind), do: []

  defp ensure_revision(cs, :modules, record) when not is_nil(record) do
    if Changeset.changed?(cs, :version), do: cs, else: Changeset.optimistic_lock(cs, :version, &((&1 || 1) + 1))
  end

  defp ensure_revision(cs, _, _), do: cs

  # After the commit: caches, the entries that render the definition, and
  # open forms. Palettes and containers re-render the entries that use them
  # as an admin save does; their blocks keep pointing at them by id.
  defp refresh(changes) do
    changes
    |> Enum.filter(&(&1.kind in ~w(module palette container)))
    |> Enum.map(fn change ->
      try do
        refresh_change(change)
      rescue
        error -> %{uid: change.uid, status: :failed, error: Exception.message(error)}
      end
    end)
  end

  defp refresh_change(%{kind: "module"} = change) do
    module = Repo.get!(Module, change.id)
    Brando.Cache.Query.evict({:ok, module})
    if change.action == :update, do: Blocks.render_entries_with_module_id(module.id)
    event = if change.action == :create, do: :created, else: :updated
    Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:modules", {module, [:module, event]})
    %{uid: change.uid, status: :requested, stale_block_ids: Blocks.list_stale_block_ids(module)}
  end

  defp refresh_change(%{kind: "palette"} = change) do
    palette = Repo.get!(Palette, change.id)
    Brando.Cache.Query.evict({:ok, palette})
    Brando.Cache.Palettes.update({:ok, palette})
    if change.action == :update, do: Brando.Content.render_entries_using_palette(palette)
    %{uid: change.uid, status: :requested, stale_block_ids: []}
  end

  defp refresh_change(%{kind: "container"} = change) do
    container = Repo.get!(Container, change.id)
    Brando.Cache.Query.evict({:ok, container})
    if change.action == :update, do: Blocks.render_entries_with_container_id(container.id)
    %{uid: change.uid, status: :requested, stale_block_ids: []}
  end

  defp validate_template!(%{"kind" => kind}, _actor) when kind in ~w(table_template palette), do: :ok

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
      Enum.map_join(
        ~w(content_modules content_table_templates content_refs content_vars content_palettes content_containers),
        ", ",
        &~s("#{prefix}"."#{&1}")
      )

    Ecto.Adapters.SQL.query!(Repo.repo(), "LOCK TABLE " <> tables <> " IN SHARE ROW EXCLUSIVE MODE", [])
  end
end
