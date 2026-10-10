defmodule Brando.Content.StaleBlocks do
  @moduledoc """
  Blocks left on an older version of their module, and what to do with the
  content that keeps them there.

  A module save migrates every block that uses it (`Blocks.sync_module/2`),
  but never deletes: a ref or var the module no longer defines (a
  *leftover*) stays in the block, and so does a ref whose type the module
  changed. Such a block is not stamped with the module's version and stays
  stale (`Blocks.list_stale_block_ids/2`), which is what `mix brando.doctor`
  counts. This module lists those blocks with what they hold, and resolves
  each leftover: **drop** it, or **map** it onto a ref or var the module
  defines now (a rename), moving its value when the types allow it.

  Resolving is a change to entries' content made outside their editors, so
  `apply/4`:

    * checks the actor may update the module and every entry it touches,
      entries in the trash included;
    * stores a revision of each entry before changing it, so History can
      restore it, and one after. An entry whose schema keeps no revisions
      (a template) gets none; the plan's entries say which with
      `revisioned?`, and which are in the trash with `trashed?`;
    * re-syncs the blocks (`Blocks.sync_module/2`), stamps them and renders
      them and their entries, as a module refresh does;
    * records the change in Activity, on the entries and on the module;
    * moves editors that have an entry open onto the new rows
      (`Brando.EditSession.sync_saved/1`).

  Everything happens in one transaction, against the current tenant prefix.
  A plan has a `fingerprint`: pass it as `expect:` and the apply is refused
  if the blocks changed after the plan was reviewed.

  ## Resolutions

  A map from a leftover to what happens to it. `{kind, key}` (kind `:ref`
  or `:var`) resolves that leftover in every block; `{block_id, kind, key}`
  overrides it for one block. The action is `:keep`, `:drop` or
  `{:map, target_key}`.

      %{{:var, "link"} => :drop, {:ref, "title"} => {:map, "heading"}}
  """
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias Brando.Authorization.Boundary
  alias Brando.Content.Block
  alias Brando.Content.BlockReferences
  alias Brando.Content.Blocks
  alias Brando.Content.Module
  alias Brando.Content.Ref
  alias Brando.Content.Usage
  alias Brando.Content.Var
  alias Brando.Repo
  alias Brando.Villain.Blocks, as: RefTypes
  alias Ecto.Changeset

  @preview_length 140

  @type kind :: :ref | :var
  @type action :: :keep | :drop | {:map, String.t()}
  @type resolutions :: %{optional({kind(), String.t()} | {integer(), kind(), String.t()}) => action()}

  ## Listing

  @doc "Every local module with blocks on an older version: `[%{module: module, count: count}]`, most first."
  @spec modules() :: [%{module: Module.t(), count: pos_integer()}]
  def modules,
    do: Enum.map(Blocks.count_stale_blocks_by_module(), fn {module, count} -> %{module: module, count: count} end)

  @doc """
  The stale blocks of a module (given as a struct, id or uid), each with
  the entries it sits in and what keeps it stale, and the leftovers grouped
  by key with the module's refs or vars they could be mapped onto.
  """
  @spec report(Module.t() | integer() | String.t(), term()) :: {:ok, map()} | {:error, String.t()}
  def report(module, actor) do
    with {:ok, module} <- fetch_module(module),
         :ok <- authorize_module(actor, :read, module) do
      {:ok, build_report(module, load_blocks(module))}
    end
  end

  @doc "The number of blocks behind `module`'s version."
  @spec count(Module.t() | integer()) :: non_neg_integer()
  def count(module), do: Blocks.count_stale_blocks(module)

  ## Planning

  @doc """
  What `resolutions` would do to the blocks of `report`: the changes, what
  each loses or replaces, the mappings refused and why, which blocks end on
  the module's version and which stay behind.
  """
  @spec plan(map(), resolutions()) :: map()
  def plan(%{module: module, blocks: blocks} = report, resolutions) do
    per_block = Enum.map(blocks, &plan_block(&1, module, report.defined, resolutions))
    changes = Enum.flat_map(per_block, & &1.changes)
    changed = for b <- per_block, b.changes != [] or b.resync?, do: b.id
    stamped = for b <- per_block, b.stamps?, do: b.id

    %{
      module: module,
      blocks: per_block,
      changes: changes,
      refused: Enum.flat_map(per_block, & &1.refused),
      changed: changed,
      stamped: stamped,
      remaining: Enum.map(blocks, & &1.id) -- stamped,
      entries:
        blocks |> Enum.filter(&(&1.id in changed)) |> Enum.flat_map(& &1.entries) |> Enum.uniq_by(&{&1.schema, &1.id}),
      lost: Enum.filter(changes, &(&1.lost || &1.replaces)),
      fingerprint: fingerprint(module, blocks)
    }
  end

  ## Applying

  @doc """
  Resolves the stale blocks of `module` as `resolutions` say (see the
  moduledoc). Refused while any mapping is refused, or when `expect:` is
  given and the blocks changed since that plan.

  Returns `{:ok, %{changed: ids, stamped: ids, remaining: ids, entries: entries}}`.
  """
  @spec apply(Module.t() | integer() | String.t(), resolutions(), term(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def apply(module, resolutions, actor, opts \\ []) do
    with {:ok, module} <- fetch_module(module),
         :ok <- authorize_module(actor, :update, module) do
      Repo.transaction(fn -> resolve!(module, resolutions, actor, opts) end)
    end
  end

  defp resolve!(module, resolutions, actor, opts) do
    lock_blocks(module)
    plan = module |> build_report(load_blocks(module)) |> plan(resolutions)

    with :ok <- check_expected(plan, opts[:expect]),
         :ok <- check_refused(plan),
         :ok <- authorize_entries(actor, plan.entries) do
      write!(plan, actor)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp check_expected(_plan, nil), do: :ok
  defp check_expected(%{fingerprint: fingerprint}, fingerprint), do: :ok

  defp check_expected(_plan, _expected),
    do: {:error, gettext("The blocks changed after you reviewed them. Review them again.")}

  defp check_refused(%{refused: []}), do: :ok

  defp check_refused(%{refused: refused}),
    do: {:error, refused |> Enum.map(&refusal_line/1) |> Enum.uniq() |> Enum.join(" ")}

  @doc "A refused mapping as one line."
  def refusal_line(%{kind: kind, key: key, target: target, reason: reason}),
    do:
      gettext("%{kind} %{key} → %{target}: %{reason}.", kind: kind_label(kind), key: key, target: target, reason: reason)

  defp write!(%{changed: []} = plan, _actor), do: result(plan)

  defp write!(plan, actor) do
    user = user(actor)
    entries = load_entries(plan.entries)

    before =
      Map.new(entries, fn {key, entry} ->
        {key,
         revision!(
           entry,
           user,
           gettext("Before resolving blocks on older versions of %{module}", module: module_name(plan.module))
         )}
      end)

    Enum.each(plan.changes, &change!/1)
    module = Repo.preload(plan.module, [:vars, refs: Ref.preloads()], force: true)

    plan.changed
    |> load_for_sync()
    |> Enum.each(fn block ->
      case block |> Blocks.sync_module(module) |> Repo.update() do
        {:ok, _} -> :ok
        {:error, changeset} -> Repo.rollback(sync_error(block, changeset))
      end
    end)

    Blocks.render_blocks(plan.changed)

    # Every owner, those in the trash too: one restored from it shows the
    # resolved blocks.
    plan.entries
    |> Enum.group_by(& &1.schema, & &1.id)
    |> Blocks.enqueue_entry_map_for_render()

    details = activity_details(plan)

    Enum.each(entries, fn {key, entry} ->
      entry = reload_entry(entry)
      revision = revision!(entry, user, nil, true)
      record_entry(entry, user, revision || before[key], details)
      Brando.EditSession.sync_saved(entry)
      Repo.after_commit(fn -> Brando.Cache.Query.evict({:ok, entry}) end)
    end)

    Brando.Activity.setting_changed(:updated, plan.module, module_name(plan.module), user, details: details)
    result(plan)
  end

  defp result(plan) do
    %{changed: plan.changed, stamped: plan.stamped, remaining: plan.remaining, entries: plan.entries}
  end

  defp sync_error(block, changeset),
    do: gettext("Block #%{id} could not be saved: %{errors}", id: block.id, errors: error_lines(changeset))

  # The changes of one block: dropping deletes the row; mapping renames it
  # to the target (taking the place of the block's own copy of the target,
  # if it has one) and converts the value when the types differ.
  defp change!(%{action: :drop, row: row}), do: Repo.delete!(row)

  defp change!(%{action: {:map, target}, row: %Var{} = var} = change) do
    if change.replaced_row, do: Repo.delete!(change.replaced_row)

    var
    |> Changeset.change(Map.merge(%{key: target, type: change.target_type}, change.convert || %{}))
    |> Repo.update!()
  end

  defp change!(%{action: {:map, target}, row: %Ref{} = ref} = change) do
    if change.replaced_row, do: Repo.delete!(change.replaced_row)
    ref |> Changeset.change(name: target) |> Repo.update!()
  end

  defp revision!(%schema{} = entry, user, description, active? \\ false) do
    if schema.has_trait(Brando.Trait.Revisioned) do
      entry |> Brando.Revisions.create_revision(user, active?) |> stored_revision!(entry, description)
    end
  end

  defp stored_revision!({:ok, revision}, %schema{} = entry, description) do
    if description, do: Brando.Revisions.describe_revision(schema, entry.id, revision.revision, description)
    revision.revision
  end

  defp stored_revision!({:error, reason}, entry, _description),
    do:
      Repo.rollback(
        gettext("Could not store a revision of %{entry}: %{reason}", entry: entry.id, reason: inspect(reason))
      )

  defp record_entry(%schema{} = entry, user, revision, details) do
    if Brando.Activity.logged?(schema),
      do: Brando.Activity.record(:updated, entry, user, revision: revision, details: details)
  end

  defp activity_details(plan) do
    {dropped, mapped} =
      plan.changes
      |> Enum.uniq_by(&{&1.kind, &1.key, &1.action})
      |> Enum.split_with(&(&1.action == :drop))

    %{
      "stale_blocks" => %{
        "module" => module_name(plan.module),
        "uid" => plan.module.uid,
        "blocks" => plan.changed,
        "dropped" => Enum.map(dropped, &"#{&1.kind}:#{&1.key}"),
        "mapped" => Enum.map(mapped, fn %{action: {:map, target}} = c -> "#{c.kind}:#{c.key}→#{target}" end)
      }
    }
  end

  ## Reading

  defp fetch_module(%Module{id: id}), do: fetch_module(id)

  defp fetch_module(id) when is_integer(id) do
    case Repo.get(Module, id) do
      nil -> {:error, gettext("No module with id %{id}.", id: id)}
      module -> {:ok, preload_module(module)}
    end
  end

  defp fetch_module(uid) when is_binary(uid) do
    case Repo.one(from(m in Module, where: m.uid == ^uid and is_nil(m.deleted_at))) do
      nil -> {:error, gettext("No module with uid %{uid}.", uid: uid)}
      module -> {:ok, preload_module(module)}
    end
  end

  defp preload_module(module), do: Repo.preload(module, [:vars, refs: Ref.preloads()])

  defp lock_blocks(module) do
    ids = Blocks.list_stale_block_ids(module)
    Repo.all(from(b in Block, where: b.id in ^ids, select: b.id, lock: "FOR UPDATE"))
  end

  defp load_blocks(module) do
    ids = Blocks.list_stale_block_ids(module)

    from(b in Block, where: b.id in ^ids, order_by: [asc: b.id], preload: [vars: ^vars_query(), refs: ^refs_query()])
    |> Repo.all()
  end

  defp vars_query, do: from(v in Var, order_by: [asc: v.sequence, asc: v.id], preload: ^Var.preloads())
  defp refs_query, do: from(r in Ref, order_by: [asc: r.sequence, asc: r.id], preload: ^Ref.preloads())

  defp load_for_sync(ids) do
    Repo.all(from(b in Block, where: b.id in ^ids, preload: [:vars, refs: ^Ref.preloads()]))
  end

  defp build_report(module, blocks) do
    defined = %{
      ref: Map.new(module.refs, &{&1.name, &1}),
      var: Map.new(module.vars, &{&1.key, &1})
    }

    entries_by_block = entries_for(Enum.map(blocks, & &1.id))

    reports =
      Enum.map(blocks, fn block ->
        leftovers = leftovers(block, defined)

        %{
          id: block.id,
          uid: block.uid,
          parent_id: block.parent_id,
          module_version: block.module_version,
          entries: Map.get(entries_by_block, block.id, []),
          leftovers: leftovers,
          rows: block,
          problems: problems(block, module, leftovers)
        }
      end)

    %{
      module: module,
      version: module.version || 1,
      defined: defined,
      blocks: reports,
      groups: groups(reports, defined)
    }
  end

  # Every ref and var the module does not back: unknown names and keys, and
  # refs whose type the module changed.
  defp leftovers(block, defined) do
    refs =
      for ref <- block.refs, leftover = ref_leftover(ref, defined.ref), do: leftover

    vars =
      for var <- block.vars, not Map.has_key?(defined.var, var.key) do
        %{
          kind: :var,
          key: var.key,
          type: var.type,
          reason: :undefined,
          defined_type: nil,
          preview: var_preview(var),
          row: var
        }
      end

    refs ++ vars
  end

  defp ref_leftover(ref, defined_refs) do
    type = ref_type(ref)

    case Map.get(defined_refs, ref.name) do
      nil ->
        %{
          kind: :ref,
          key: ref.name,
          type: type,
          reason: :undefined,
          defined_type: nil,
          preview: ref_preview(ref),
          row: ref
        }

      source ->
        unless RefTypes.ref_types_compatible?(data_struct(source), data_struct(ref)) do
          %{
            kind: :ref,
            key: ref.name,
            type: type,
            reason: :retyped,
            defined_type: ref_type(source),
            preview: ref_preview(ref),
            row: ref
          }
        end
    end
  end

  # What else keeps a block from being stamped: a re-sync that would not
  # save. A block with nothing left over and nothing else in the way only
  # needs the re-sync a resolve runs.
  defp problems(block, module, []) do
    case Blocks.sync_module(block, module) do
      %Changeset{valid?: true} ->
        []

      changeset ->
        [gettext("It cannot be saved as it is: %{errors}", errors: error_lines(changeset))]
    end
  rescue
    error -> [gettext("It cannot be updated: %{error}", error: Exception.message(error))]
  end

  defp problems(_block, _module, _leftovers), do: []

  defp error_lines(changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, _} -> message end)
    |> inspect()
  end

  defp groups(reports, defined) do
    reports
    |> Enum.flat_map(fn report -> Enum.map(report.leftovers, &Map.put(&1, :block_id, report.id)) end)
    |> Enum.group_by(&{&1.kind, &1.key})
    |> Enum.map(fn {{kind, key}, leftovers} ->
      types = leftovers |> Enum.map(& &1.type) |> Enum.uniq()

      %{
        kind: kind,
        key: key,
        types: types,
        reason: hd(leftovers).reason,
        defined_type: hd(leftovers).defined_type,
        blocks: leftovers |> Enum.map(& &1.block_id) |> Enum.uniq(),
        targets: targets(kind, key, types, defined)
      }
    end)
    |> Enum.sort_by(&{&1.kind, &1.key})
  end

  @doc """
  The refs or vars of the module a leftover of `kind` and `types` could be
  mapped onto: `[%{key, type, ok?: boolean, reason: nil | String.t()}]`.
  """
  def targets(kind, key, types, defined) do
    defined
    |> Map.fetch!(kind)
    |> Map.values()
    |> Enum.reject(&(target_key(&1) == key))
    |> Enum.sort_by(&{&1.sequence || 0, target_key(&1)})
    |> Enum.map(fn target ->
      reason = Enum.find_value(types, &type_refusal(kind, &1, target))
      %{key: target_key(target), type: defined_type(target), ok?: is_nil(reason), reason: reason}
    end)
  end

  defp target_key(%Ref{name: name}), do: name
  defp target_key(%Var{key: key}), do: key

  defp defined_type(%Ref{} = ref), do: ref_type(ref)
  defp defined_type(%Var{type: type}), do: type

  defp type_refusal(:ref, type, target) do
    unless RefTypes.ref_types_compatible?(data_struct(target), ref_struct(type)),
      do: gettext("a %{from} reference cannot hold the content of a %{to} reference", from: ref_type(target), to: type)
  end

  defp type_refusal(:var, type, target) do
    case var_conversion(type, target.type) do
      :error -> gettext("a %{from} variable cannot become a %{to} variable", from: type, to: target.type)
      _ -> nil
    end
  end

  ## One block's plan

  defp plan_block(report, module, defined, resolutions) do
    {changes, refused, _claimed} =
      Enum.reduce(report.leftovers, {[], [], MapSet.new()}, &plan_leftover(&1, &2, report, defined, resolutions))

    resolved = MapSet.new(changes, &{&1.kind, &1.row.id})
    remaining = Enum.reject(report.leftovers, &MapSet.member?(resolved, {&1.kind, &1.row.id}))

    %{
      id: report.id,
      entries: report.entries,
      changes: Enum.reverse(changes),
      refused: Enum.reverse(refused),
      remaining: remaining,
      # Nothing left over: the re-sync alone brings it up to date.
      resync?: report.leftovers == [] and report.problems == [],
      stamps?: remaining == [] and refused == [] and report.problems == [],
      version: {report.module_version, module.version || 1}
    }
  end

  # `claimed`: the targets a mapping in this block already moves something into.
  defp plan_leftover(leftover, {changes, refused, claimed}, report, defined, resolutions) do
    case action(resolutions, report.id, leftover) do
      :keep ->
        {changes, refused, claimed}

      :drop ->
        {[change(report, leftover, :drop) | changes], refused, claimed}

      {:map, target} ->
        case map_change(report, leftover, target, defined, claimed, resolutions) do
          {:ok, change} -> {[change | changes], refused, MapSet.put(claimed, {leftover.kind, target})}
          {:error, reason} -> {changes, [refusal(report, leftover, target, reason) | refused], claimed}
        end
    end
  end

  defp action(resolutions, block_id, %{kind: kind, key: key}) do
    Map.get(resolutions, {block_id, kind, key}) || Map.get(resolutions, {kind, key}) || :keep
  end

  defp change(report, leftover, action) do
    %{
      block_id: report.id,
      kind: leftover.kind,
      key: leftover.key,
      type: leftover.type,
      action: action,
      row: leftover.row,
      lost: if(action == :drop and leftover.preview != "", do: leftover.preview),
      replaces: nil,
      replaced_row: nil,
      target_type: nil,
      convert: nil,
      entries: report.entries
    }
  end

  defp refusal(report, leftover, target, reason),
    do: %{block_id: report.id, kind: leftover.kind, key: leftover.key, target: target, reason: reason}

  defp map_change(report, leftover, target, defined, claimed, resolutions) do
    source = Map.get(Map.fetch!(defined, leftover.kind), target)
    existing = existing_row(report.rows, leftover.kind, target)
    in_the_way? = existing && retyped?(report, leftover.kind, target)

    with :ok <- check_target(leftover, target, source, claimed),
         :ok <- check_in_the_way(in_the_way?, report, leftover.kind, target, resolutions),
         {:ok, convert} <- convert(leftover, source) do
      replaced = existing && preview(existing)

      {:ok,
       %{
         change(report, leftover, {:map, target})
         | replaces: if(replaced not in [nil, "", preview(source)], do: replaced),
           replaced_row: if(existing && !in_the_way?, do: existing),
           target_type: defined_type(source),
           convert: convert
       }}
    end
  end

  defp check_target(leftover, target, source, claimed) do
    cond do
      is_nil(source) ->
        {:error,
         gettext("the module has no %{kind} %{key}", kind: String.downcase(kind_label(leftover.kind)), key: target)}

      target == leftover.key ->
        {:error, gettext("it already has that name")}

      MapSet.member?(claimed, {leftover.kind, target}) ->
        {:error, gettext("another leftover in this block is moved into %{key}", key: target)}

      reason = type_refusal(leftover.kind, leftover.type, source) ->
        {:error, reason}

      true ->
        :ok
    end
  end

  # The block's own `target` holds content of another type (a retyped ref):
  # only a drop of it makes room.
  defp check_in_the_way(false, _report, _kind, _target, _resolutions), do: :ok
  defp check_in_the_way(nil, _report, _kind, _target, _resolutions), do: :ok

  defp check_in_the_way(true, report, kind, target, resolutions) do
    if action(resolutions, report.id, %{kind: kind, key: target}) == :drop,
      do: :ok,
      else: {:error, gettext("%{key} holds content of another type; drop that first", key: target)}
  end

  defp existing_row(block, :ref, name), do: Enum.find(block.refs, &(&1.name == name))
  defp existing_row(block, :var, key), do: Enum.find(block.vars, &(&1.key == key))

  defp retyped?(report, kind, key), do: Enum.any?(report.leftovers, &(&1.kind == kind and &1.key == key))

  defp preview(%Ref{} = ref), do: ref_preview(ref)
  defp preview(%Var{} = var), do: var_preview(var)

  ## Var conversions

  # A var keeps its value when it moves to a var of the same type, or of a
  # type that holds it without loss.
  defp var_conversion(same, same), do: :same
  defp var_conversion(:string, :text), do: :same
  defp var_conversion(:text, :string), do: :single_line
  defp var_conversion(from, :html) when from in [:string, :text], do: :to_html
  defp var_conversion(_from, _to), do: :error

  defp convert(%{kind: :ref}, _source), do: {:ok, nil}

  defp convert(%{kind: :var, row: var}, source) do
    with :ok <- check_option(var, source) do
      var |> var_conversion_of(source) |> converted(var)
    end
  end

  defp var_conversion_of(var, source), do: var_conversion(var.type, source.type)

  defp converted(:same, _var), do: {:ok, nil}
  defp converted(:to_html, var), do: {:ok, %{value: to_html(var.value)}}

  defp converted(:single_line, var) do
    if String.contains?(var.value || "", "\n"),
      do: {:error, gettext("its text has more than one line")},
      else: {:ok, nil}
  end

  defp check_option(%Var{value: value}, %Var{type: :select, options: [_ | _] = options}) when value not in [nil, ""] do
    if Enum.any?(options, &(&1.value == value)),
      do: :ok,
      else: {:error, gettext("“%{value}” is not one of its options", value: value)}
  end

  defp check_option(_var, _source), do: :ok

  defp to_html(nil), do: nil
  defp to_html(""), do: ""

  defp to_html(text) do
    text
    |> String.split(~r/\R/)
    |> Enum.map_join("<br>", &(&1 |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()))
    |> then(&"<p>#{&1}</p>")
  end

  ## Entries

  defp entries_for([]), do: %{}

  # Entries in the trash own their blocks too: a resolve changes them like
  # any other, and restoring one from the trash brings back what it held.
  defp entries_for(block_ids) do
    by_block = BlockReferences.list_entries_for_block_ids(block_ids, include_deleted: true)
    entries = by_block |> Map.values() |> List.flatten() |> Enum.uniq()
    labels = Usage.labels(entries)
    states = states(entries)

    Map.new(by_block, fn {block_id, entries} ->
      {block_id, Enum.map(entries, &entry(&1, labels[&1], Map.get(states, &1, %{})))}
    end)
  end

  # `revisioned?`: History can restore it (not every schema with blocks
  # keeps revisions: templates do not).
  defp entry({schema, id}, label, state) do
    trashed? = Map.get(state, :deleted_at) != nil

    label
    |> Map.merge(%{
      schema: schema,
      id: id,
      trashed?: trashed?,
      revisioned?: schema.has_trait(Brando.Trait.Revisioned)
    })
    |> Map.update(:language, nil, &(&1 || Map.get(state, :language)))
    |> Map.update(:url, nil, &if(trashed?, do: trash_url(&1), else: &1))
  end

  # The listing's trash: an entry in it has no edit page.
  defp trash_url(nil), do: nil
  defp trash_url(url), do: String.replace(url, ~r{/update/\d+$}, "") <> "?status=deleted"

  # What an entry's identifier row does not say: its language (an entry
  # without one has it only on itself) and whether it is in the trash.
  defp states(entries) do
    entries
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {schema, ids} ->
      fields = Enum.filter([:id, :language, :deleted_at], &(&1 in schema.__schema__(:fields)))

      from(e in schema, where: e.id in ^ids, select: map(e, ^fields))
      |> Repo.all()
      |> Enum.map(&{{schema, &1.id}, &1})
    end)
    |> Map.new()
  end

  defp load_entries(entries) do
    Map.new(entries, fn %{schema: schema, id: id} ->
      {{schema, id}, Repo.get!(schema, id)}
    end)
  end

  defp reload_entry(%schema{id: id}), do: Repo.get!(schema, id)

  ## Authorization

  defp authorize_module(actor, action, module) do
    if Boundary.authorize_record(actor, action, Module, module.id) == :ok,
      do: :ok,
      else: {:error, gettext("You do not have permission to change this module.")}
  end

  defp authorize_entries(actor, entries) do
    case Enum.find(entries, &(Boundary.authorize_record(actor, :update, &1.schema, &1.id) != :ok)) do
      nil -> :ok
      entry -> {:error, gettext("You do not have permission to change %{entry}.", entry: entry.label)}
    end
  end

  defp user(:system), do: nil
  defp user(user), do: user

  ## Previews

  @doc "A short, readable preview of a var's value."
  def var_preview(%Var{type: :boolean, value_boolean: value}), do: if(value, do: gettext("Yes"), else: gettext("No"))
  def var_preview(%Var{type: :html, value: value}), do: plain(value)

  def var_preview(%Var{type: :link} = var) do
    target =
      case var.identifier do
        %{title: title} when is_binary(title) -> title
        _ -> var.value
      end

    [var.link_text, target] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" → ") |> plain()
  end

  def var_preview(%Var{type: :image} = var), do: media_name(var.image, var.image_id)
  def var_preview(%Var{type: :file} = var), do: media_name(var.file, var.file_id)
  def var_preview(%Var{type: :video} = var), do: media_name(var.video, var.video_id)
  def var_preview(%Var{type: :gallery} = var), do: gallery_preview(var.gallery, var.gallery_id)
  def var_preview(%Var{type: :form} = var), do: media_name(var.form, var.form_id)
  def var_preview(%Var{value: value}), do: plain(value)

  @doc "A short, readable preview of a ref's content."
  def ref_preview(%Ref{data: %{data: %{} = data}} = ref) do
    text = Enum.find_value(~w(text html code title caption url source embed_url)a, &present(Map.get(data, &1)))

    if text, do: plain(text), else: media_preview(ref)
  end

  def ref_preview(_ref), do: ""

  # The first of the ref's media that is set.
  defp media_preview(ref) do
    [image: &media_name/2, video: &media_name/2, file: &media_name/2, gallery: &gallery_preview/2]
    |> Enum.find_value("", fn {field, preview} ->
      media = Map.get(ref, field)
      id = Map.get(ref, :"#{field}_id")
      if loaded?(media) or id, do: preview.(media, id)
    end)
  end

  defp media_name(%{path: path}, _id) when is_binary(path), do: Path.basename(path)
  defp media_name(%{filename: name}, _id) when is_binary(name), do: name
  defp media_name(%{title: title}, _id) when is_binary(title) and title != "", do: plain(title)
  defp media_name(%{name: name}, _id) when is_binary(name), do: name
  defp media_name(_media, nil), do: ""
  defp media_name(_media, id), do: "##{id}"

  defp gallery_preview(%{gallery_objects: objects}, _id) when is_list(objects),
    do: ngettext("%{count} item", "%{count} items", length(objects))

  defp gallery_preview(_gallery, nil), do: ""
  defp gallery_preview(_gallery, id), do: "##{id}"

  defp loaded?(%Ecto.Association.NotLoaded{}), do: false
  defp loaded?(nil), do: false
  defp loaded?(_), do: true

  defp present(value) when is_binary(value), do: if(String.trim(value) != "", do: value)
  defp present(_), do: nil

  defp plain(nil), do: ""

  defp plain(text) when is_binary(text) do
    text
    |> HtmlSanitizeEx.strip_tags()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> Brando.Utils.truncate(@preview_length, "…")
  end

  defp plain(other), do: other |> to_string() |> plain()

  ## Names

  @doc "What a ref's content is: `text`, `picture`, … (`nil` when unknown)."
  def ref_type(%Ref{} = ref), do: ref |> data_struct() |> type_name()

  defp data_struct(%Ref{data: %{__struct__: struct}}), do: struct
  defp data_struct(_), do: nil

  defp ref_struct(nil), do: nil
  defp ref_struct(type), do: Keyword.get(RefTypes.list_blocks(), String.to_existing_atom(type))

  defp type_name(nil), do: nil

  defp type_name(struct),
    do: Enum.find_value(RefTypes.list_blocks(), fn {name, mod} -> mod == struct && to_string(name) end)

  @doc "Reference or Variable."
  def kind_label(:ref), do: gettext("Reference")
  def kind_label(:var), do: gettext("Variable")

  @doc "The module's name in the admin's language."
  def module_name(%{name: name}) when is_map(name), do: Brando.Type.I18nString.get(name, nil) || "-"
  def module_name(%{name: name}), do: to_string(name)

  # Of everything the rows hold, not of their previews: a preview is plain
  # text cut short, and does not show a link's URL or which image it is.
  defp fingerprint(module, blocks) do
    :erlang.phash2({
      module.version,
      Enum.map(blocks, fn b ->
        {b.id, b.module_version, b.problems, Enum.map(b.entries, &{&1.schema, &1.id, &1.trashed?}),
         Enum.map(b.leftovers, &{&1.kind, &1.key, &1.type, &1.row.id}), Enum.map(b.rows.vars, &stored/1),
         Enum.map(b.rows.refs, &stored/1)}
      end)
    })
  end

  defp stored(%schema{} = row), do: Map.take(row, schema.__schema__(:fields))
end
