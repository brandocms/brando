defmodule Brando.Content.Transfer do
  use Gettext, backend: Brando.Gettext

  @moduledoc """
  Transfer complete saved entries or selected block fields between environments.

  Export complete entries with `%{schema: Schema, id: id}`. Explicit `fields`
  selectors retain the version-1 block-field workflow; `scope: :entries` forces
  complete entries. Version-2 targets use `mode: create/update`, optional entry
  `id`, reviewed `attributes` and `publication: draft/preserve/source`.
  `preview/4` accepts an archive returned by `read/1`, destination mappings keyed
  by source entry or field key, and dependency mappings keyed by portable token. Plans
  are read-only, scoped to their actor, and checked again inside the apply
  transaction. Retrying one plan returns its receipt; a new preview is an
  intentional new operation. See the content transfer guide.
  """
  import Ecto.Query, only: [from: 2]
  alias Brando.Activity
  alias Brando.Authorization.Boundary
  alias Brando.Content.Block
  alias Brando.Content.Definition.{References, Snapshot, Value}
  alias Brando.Content.Transfer.{Archive, Catalog, Contracts, Dependencies, Error, Media, Portable, Receipt}
  alias Brando.Drafts.Params
  alias Brando.Repo
  alias Ecto.Changeset

  defdelegate read(binary), to: Archive
  defdelegate max_bytes(), to: Archive
  defdelegate search(actor, query, opts), to: Catalog
  def scope, do: References.scope()

  def export(selectors, actor, opts \\ []) do
    with {:ok, exported} <- Error.protect(fn -> export!(selectors, actor, opts) end),
         {:ok, binary} <- Archive.export(exported.bundle, exported.files) do
      {:ok, Map.put(exported, :binary, binary)}
    end
  end

  defp export!(selectors, actor, opts) do
    ensure_scope!(actor)
    if selectors == [], do: Error.fail!(dgettext("content_transfer", "Select at least one entry."))
    whole_entries? = Keyword.get(opts, :scope) == :entries || Enum.any?(selectors, &(!Map.has_key?(&1, :fields)))

    {entries, state} =
      if whole_entries?,
        do: Brando.Content.Transfer.Entries.take!(selectors, actor, opts),
        else: {nil, Dependencies.new(actor, opts)}

    {fields, state} =
      if entries do
        {Brando.Content.Transfer.Entries.fields(entries), state}
      else
        Enum.flat_map_reduce(selectors, state, &export_selector_fields(&1, &2, actor))
      end

    uids = for {_, %{"kind" => "module", "uid" => uid}} <- state.dependencies, do: uid

    {definitions, state} =
      if Keyword.get(opts, :definitions, true) && uids != [] do
        export_definitions!(uids, state, actor)
      else
        {nil, state}
      end

    bundle = export_bundle(entries, fields, state.dependencies, definitions, opts)
    Portable.validate!(bundle)
    %{bundle: bundle, files: state.files}
  end

  defp export_bundle(entries, fields, dependencies, definitions, opts) do
    bundle = %{
      "format" => "brando-content",
      "version" => if(entries, do: 2, else: 1),
      "id" => Ecto.UUID.generate(),
      "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "source" => %{
        "scope" => scope(),
        "label" => Keyword.get(opts, :source_label, Brando.config(:app_name) || "Brando"),
        "brando_version" => Brando.version()
      },
      "fields" => fields,
      "dependencies" => dependencies,
      "definitions" => definitions
    }

    if entries, do: Map.put(bundle, "entries", entries), else: bundle
  end

  defp export_selector_fields(selector, state, actor) do
    entry = Catalog.load!(selector.schema, selector.id, actor, :export)
    description = Catalog.describe(entry)
    Enum.map_reduce(selector.fields, state, &export_field(entry, description, &1, &2))
  end

  defp export_field(entry, description, name, acc) do
    field = Catalog.field!(entry.__struct__, name)
    joins = Map.fetch!(entry, field.association)
    {blocks, acc} = Enum.map_reduce(joins, acc, &Portable.encode(&1.block, &2))

    {%{
       "key" => description.key <> ":" <> field.name,
       "schema" => description.schema,
       "field" => field.name,
       "title" => description.title,
       "language" => description.language,
       "hints" => description.hints,
       "blocks" => blocks,
       "fingerprint" => Value.digest(blocks)
     }, acc}
  end

  defp export_definitions!(uids, state, actor) do
    {definitions, records} = Snapshot.take!(uids: uids)
    Enum.each(definitions["modules"], &Catalog.authorize!(actor, :export, records.modules[&1["uid"]]))
    Enum.each(definitions["table_templates"], &Catalog.authorize!(actor, :export, records.tables[&1["uid"]]))

    state =
      Enum.reduce(definitions["references"], state, fn {_, ref}, acc ->
        {_token, acc} = Dependencies.add(ref["kind"], ref["id"], acc)
        acc
      end)

    {definitions, state}
  end

  def preview(archive, targets, actor, opts \\ []) do
    Error.protect(fn -> preview!(archive, targets, actor, opts) end)
  end

  defp preview!(%{bundle: %{"version" => 2}} = archive, targets, actor, opts),
    do: Brando.Content.Transfer.Entries.preview!(archive, targets, actor, opts)

  defp preview!(archive, targets, actor, opts) do
    ensure_scope!(actor)
    operation_id = Keyword.get(opts, :operation_id, Ecto.UUID.generate())

    unless match?({:ok, _}, Ecto.UUID.cast(operation_id)),
      do: Error.fail!(dgettext("content_transfer", "Invalid import operation ID."))

    bundle = Portable.validate!(archive.bundle)
    supplied = Keyword.get(opts, :dependencies, %{})
    {items, bindings} = resolve_dependencies(bundle, supplied, archive.files, actor)

    fields = Enum.map(bundle["fields"], &preview_field(&1, targets[&1["key"]], actor))
    fields = validate_fields(fields, bundle, bindings, actor)
    problems = preview_problems(items, fields)

    fingerprint =
      Value.digest(%{
        "scope" => scope(),
        "bundle" => bundle,
        "targets" => targets,
        "supplied" => supplied,
        "fields" => Enum.map(fields, &Map.take(&1, [:before, :mode, :issue])),
        "dependencies" => Enum.map(items, &Map.take(&1, [:token, :id, :fingerprint, :action, :issue]))
      })

    %{
      id: operation_id,
      actor_id: actor_id!(actor),
      scope: scope(),
      archive: archive,
      targets: targets,
      supplied: supplied,
      fields: fields,
      dependencies: items,
      bindings: bindings,
      problems: Enum.uniq(problems),
      fingerprint: fingerprint
    }
  end

  defp preview_field(source, selected, actor) do
    candidates =
      case Error.protect(fn -> Catalog.candidates(source, actor) end) do
        {:ok, candidates} -> candidates
        _ -> []
      end

    case Error.protect(fn -> preview_destination!(source, selected, actor) end) do
      {:ok, destination} ->
        Map.merge(destination, %{
          source: source,
          candidates: candidates,
          issue: nil,
          incoming_count: Portable.count(source["blocks"])
        })

      {:error, message} ->
        %{
          source: source,
          candidates: candidates,
          issue: message,
          incoming_count: Portable.count(source["blocks"]),
          destination: nil
        }
    end
  end

  defp preview_destination!(source, selected, actor) do
    unless is_map(selected),
      do: Error.fail!(dgettext("content_transfer", "Choose a destination entry and block field."))

    mode = selected["mode"] || "replace"

    unless mode in ["replace", "append"],
      do: Error.fail!(dgettext("content_transfer", "Choose Replace or Append."))

    entry = Catalog.load!(selected["schema"] || source["schema"], selected["id"], actor, :update)
    field = Catalog.field!(entry.__struct__, selected["field"] || source["field"])
    current = Map.fetch!(entry, field.association)
    description = Catalog.describe(entry)
    # Include owning entry state (status, module-set constraints and custom
    # validations) as well as the complete saved field in the preview lease.
    %{
      entry: entry,
      field: field,
      mode: mode,
      current: current,
      destination: description,
      before: entry_fingerprint(entry),
      current_count: current |> Enum.map(& &1.block) |> Enum.map(&Params.snapshot/1) |> Portable.count()
    }
  end

  defp preview_problems(items, fields) do
    destination_keys = for %{issue: nil} = field <- fields, do: {field.destination.key, field.field.name}
    duplicate? = length(destination_keys) != length(Enum.uniq(destination_keys))
    problems = for %{issue: issue} <- items ++ fields, issue, do: issue

    if duplicate?,
      do: [
        dgettext(
          "content_transfer",
          "Two source fields point to the same destination field. Choose distinct destinations."
        )
        | problems
      ],
      else: problems
  end

  @doc """
  Resolves each dependency the bundle requires to a reuse, create, bundle or
  unresolved action, preferring a supplied mapping, then a UID match, then a mapping
  remembered from this actor's earlier imports.

  Returns `{items, bindings}`, where bindings map tokens to the reused records.
  """
  def resolve_dependencies(bundle, supplied, files, actor, bundled \\ %{}) do
    remembered = remembered_mappings(bundle, actor)

    required = Brando.Content.Transfer.Requirements.content(bundle, Map.merge(remembered, supplied))
    context = %{supplied: supplied, remembered: remembered, bundled: bundled, files: files, actor: actor}

    Enum.map_reduce(Enum.sort(required), %{}, fn {token, dep}, bindings ->
      resolve_dependency(token, dep, bindings, context)
    end)
  end

  defp resolve_dependency(token, dep, bindings, context) do
    suggestions = Dependencies.suggestions(dep, context.actor)
    selected = selected_dependency(token, suggestions, context)
    auto_create? = auto_create?(dep)
    action = dependency_action(token, selected, auto_create?, context)

    item = %{token: token, dependency: dep, suggestions: suggestions, action: action, can_create?: auto_create?}

    case Error.protect(fn -> resolve_action!(action, token, dep, selected, context) end) do
      {:ok, {record, fingerprint}} ->
        item =
          Map.merge(item, %{
            id: record && record.id,
            fingerprint: fingerprint,
            differences: Contracts.differences(dep, record),
            issue: nil
          })

        {item, if(record, do: Map.put(bindings, token, record), else: bindings)}

      {:error, message} ->
        {Map.merge(item, %{id: nil, fingerprint: nil, differences: [], issue: message}), bindings}
    end
  end

  defp dependency_action(token, selected, auto_create?, %{supplied: supplied, bundled: bundled}) do
    from_bundle = bundled[token] && supplied[token] in [nil, "bundle"]

    cond do
      from_bundle -> :bundle
      selected && selected != "create" -> :reuse
      auto_create? -> :create
      true -> :unresolved
    end
  end

  defp selected_dependency(token, suggestions, %{supplied: supplied, remembered: remembered}) do
    uid_match = Enum.find(suggestions, &(&1.match == :uid))
    supplied[token] || (uid_match && uid_match.id) || remembered[token]
  end

  defp auto_create?(dep) do
    dep["kind"] == "gallery" || (dep["kind"] in ~w(image file) && dep["original"]) ||
      (dep["kind"] == "video" && dep["data"]["type"] in ~w(upload external_file vimeo youtube))
  end

  defp resolve_action!(:bundle, token, dep, _selected, context), do: {context.bundled[token], Value.digest(dep)}

  defp resolve_action!(:reuse, _token, dep, selected, %{actor: actor}) do
    if dep["kind"] == "gallery",
      do:
        Error.fail!(
          dgettext(
            "content_transfer",
            "Map the gallery's media assets; its owned gallery is recreated from the bundle."
          )
        )

    record = Dependencies.load!(dep, Catalog.id!(selected), actor) |> preload_dependency(dep["kind"])
    {record, Dependencies.fingerprint(record)}
  end

  defp resolve_action!(:create, _token, dep, _selected, %{files: files, actor: actor}) do
    Catalog.authorize!(actor, :create, Dependencies.schema!(dep["kind"]))
    if dep["kind"] in ~w(image file), do: Media.validate!(dep, files, actor)
    {nil, Value.digest(dep)}
  end

  defp resolve_action!(:unresolved, _token, dep, _selected, _context) do
    Error.fail!(
      dgettext("content_transfer", "Resolve %{value1} “%{value2}” on the destination.",
        value1: dep["kind"],
        value2: dep["label"]
      )
    )
  end

  defp preload_dependency(record, "module"), do: Repo.preload(record, [:vars, :refs])
  defp preload_dependency(record, "table_template"), do: Repo.preload(record, [:vars])
  defp preload_dependency(record, "module_set"), do: Repo.preload(record, :module_set_modules)
  defp preload_dependency(record, _kind), do: record

  defp validate_fields(fields, bundle, bindings, actor) do
    contracts =
      Map.new(bindings, fn {token, record} ->
        {token, if(match?(%Brando.Content.Module{}, record), do: Contracts.capture(record))}
      end)

    Enum.map(fields, &validate_field(&1, bundle, bindings, contracts, actor))
  end

  defp validate_field(%{issue: nil} = field, bundle, bindings, contracts, actor) do
    case Error.protect(fn -> validate_field!(field, bundle, bindings, contracts, actor) end) do
      {:ok, _} -> field
      {:error, message} -> %{field | issue: message}
    end
  end

  defp validate_field(field, _bundle, _bindings, _contracts, _actor), do: field

  defp validate_field!(field, bundle, bindings, contracts, actor) do
    Portable.walk(field.source["blocks"], &check_block_module!(&1, bundle, bindings, contracts))

    preview_bindings = preview_bindings(bundle, bindings)
    params = field_params([field], preview_bindings, actor)
    cs = field_changeset(field.entry, params, actor)

    unless cs.valid?,
      do:
        Error.fail!(
          dgettext("content_transfer", "Field validation: %{value1}",
            value1: inspect(Changeset.traverse_errors(cs, fn {message, _} -> message end))
          )
        )

    if Boundary.change(actor, :update, cs) != :ok,
      do: Error.fail!(dgettext("content_transfer", "You do not have permission to change this field."))

    Catalog.authorize!(actor, :update, field.entry)
  end

  defp check_block_module!(block, bundle, bindings, contracts) do
    if token = block["module_id"] do
      module =
        bindings[token] ||
          Error.fail!(dgettext("content_transfer", "Resolve the required modules before reviewing content."))

      Contracts.check!(block, bundle["dependencies"][token]["contract"], module, contracts[token])
      check_module_placement!(module, bundle["dependencies"][token], bindings)
    end
  end

  defp check_module_placement!(module, dependency, bindings) do
    parent = dependency["parent"]

    if parent && bindings[parent] && module.parent_id != bindings[parent].id,
      do: Error.fail!(dgettext("content_transfer", "The child module belongs to a different destination parent."))

    table = dependency["table_template"]

    if table && bindings[table] && module.table_template_id != bindings[table].id,
      do: Error.fail!(dgettext("content_transfer", "Map the table template used by the selected destination module."))
  end

  def applicable?(plan), do: plan.problems == []

  # Imported entries move the open editors onto their new rows once the
  # import has committed (`Brando.EditSession.written/1`).
  def apply(plan, actor), do: Brando.EditSession.collecting(fn -> protected_apply(plan, actor) end)

  defp protected_apply(plan, actor) do
    with {:ok, result} <- Error.protect(fn -> apply!(plan, actor) end), do: result
  end

  defp apply!(%{archive: %{bundle: %{"version" => 2}}} = plan, actor),
    do: Brando.Content.Transfer.Entries.apply!(plan, actor)

  defp apply!(plan, actor) do
    ensure_scope!(actor)
    authorize_plan!(plan, actor)

    Enum.each(plan.fields, fn field ->
      if field.destination, do: Catalog.load!(field.destination.schema, field.destination.id, actor, :update)
    end)

    unless applicable?(plan),
      do: Error.fail!(dgettext("content_transfer", "Resolve every blocking problem before importing."))

    case receipt(plan.id, actor) do
      %Receipt{} = receipt -> {:ok, receipt}
      nil -> apply_new!(plan, actor)
    end
  end

  defp apply_new!(plan, actor) do
    media =
      for %{action: :create, dependency: %{"kind" => kind}} = item <- plan.dependencies,
          kind in ~w(image file),
          into: %{},
          do: {item.token, item.dependency}

    stage = Media.stage!(media, plan.archive.files, actor, plan.id)

    result =
      try do
        Repo.transaction(fn ->
          Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
            "brando-content-transfer:" <> scope()
          ])

          if existing = receipt(plan.id, actor) do
            existing
          else
            apply_plan!(plan, stage, actor)
          end
        end)
      rescue
        error ->
          Media.cleanup(stage, false)
          reraise error, __STACKTRACE__
      end

    Media.cleanup(stage, match?({:ok, _}, result))

    case result do
      {:ok, receipt} -> {:ok, refresh_receipt(receipt, actor)}
      error -> error
    end
  end

  defp apply_plan!(plan, stage, actor) do
    # Lock owning rows in deterministic order; children and dependencies
    # are fingerprinted again after these locks are held.
    plan.fields
    |> Enum.sort_by(& &1.destination.key)
    |> Enum.each(&Catalog.load!(&1.destination.schema, &1.destination.id, actor, :update, lock: true))

    lock_records!(plan)

    current = preview!(plan.archive, plan.targets, actor, dependencies: plan.supplied, operation_id: plan.id)

    unless current.fingerprint == plan.fingerprint && applicable?(current),
      do: Repo.rollback("The destination changed after preview. Review the import again.")

    before = snapshot_fields(current.fields)
    bindings = persist_dependencies!(current, stage, actor)
    label = plan.archive.bundle["source"]["label"]

    Activity.with_source(:import, fn ->
      Activity.with_batch(plan.id, fn -> persist_fields!(current.fields, bindings, actor, label) end)
    end)

    after_fields =
      Enum.map(current.fields, fn field ->
        %{field | entry: Catalog.load!(field.destination.schema, field.destination.id, actor, :update)}
      end)

    Repo.insert!(plan_receipt(plan, before, after_fields, bindings, actor))
  end

  defp plan_receipt(plan, before, after_fields, bindings, actor) do
    %Receipt{
      id: plan.id,
      package_id: plan.archive.bundle["id"],
      fingerprint: plan.fingerprint,
      scope: scope(),
      actor_id: actor_id!(actor),
      before: before,
      after: snapshot_fields(after_fields),
      mappings: %{
        "source" => plan.archive.bundle["source"]["scope"],
        "transferred_media" =>
          for(
            %{action: :create, token: token, dependency: %{"kind" => kind} = dep} <- plan.dependencies,
            kind in ~w(image file),
            do: %{"kind" => kind, "id" => bindings[token].id, "sha256" => dep["original"]["sha256"]}
          ),
        "targets" => plan.targets,
        "dependencies" => Map.new(bindings, fn {token, record} -> {token, record.id} end),
        "requirements" => Map.new(plan.archive.bundle["dependencies"], fn {token, dep} -> {token, Value.digest(dep)} end),
        "created_images" =>
          for(
            %{action: :create, token: token, dependency: %{"kind" => "image"}} <- plan.dependencies,
            do: bindings[token].id
          )
      }
    }
  end

  @doc """
  Inside the apply transaction, persists bundled media and creates the dependencies
  planned for creation. Returns the plan's bindings extended with the new records.
  """
  def persist_dependencies!(plan, stage, actor) do
    bindings =
      Enum.reduce(stage.items, plan.bindings, fn {token, item}, bindings ->
        Map.put(bindings, token, Media.persist!(token, item, actor, plan.id))
      end)

    bindings =
      Enum.reduce(plan.dependencies, bindings, fn
        %{action: :create, token: token, dependency: %{"kind" => "video"} = dep}, bindings ->
          attrs = Portable.decode_values(dep["data"], bindings)
          video = %Brando.Videos.Video{} |> Brando.Videos.Video.changeset(attrs, actor) |> Repo.insert!()
          Map.put(bindings, token, video)

        _, bindings ->
          bindings
      end)

    Enum.reduce(plan.dependencies, bindings, fn
      %{dependency: %{"kind" => "gallery"}} = item, bindings -> persist_gallery!(item, bindings, actor)
      _, bindings -> bindings
    end)
  end

  defp persist_gallery!(%{token: token, dependency: dep} = item, bindings, actor) do
    # A mapped gallery is also copied: gallery ownership is per placement.
    objects =
      if item.action == :reuse do
        Repo.preload(bindings[token], :gallery_objects).gallery_objects
        |> Enum.map(fn object -> object |> Params.snapshot() |> Map.take(~w(image_id video_id sequence config)) end)
      else
        Enum.map(dep["objects"], &(Map.delete(&1, "key") |> Portable.decode_values(bindings)))
      end

    gallery =
      %Brando.Galleries.Gallery{}
      |> Brando.Galleries.Gallery.changeset(
        %{"config_target" => dep["config_target"], "gallery_objects" => objects},
        actor
      )
      |> Repo.insert!()

    Map.put(bindings, token, gallery)
  end

  defp persist_fields!(fields, bindings, actor, label) do
    available = bindings |> Map.values() |> Enum.filter(&match?(%Brando.Galleries.Gallery{}, &1)) |> MapSet.new(& &1.id)

    fields
    |> Enum.group_by(& &1.destination.key)
    |> Enum.reduce(available, fn {_, fields}, available ->
      entry = hd(fields).entry
      params = field_params(fields, bindings, actor)
      {params, available} = Brando.Content.Transfer.Ownership.galleries(params, actor, available)
      cs = field_changeset(entry, params, actor) |> stamp_versions(bindings)

      unless cs.valid?,
        do:
          Error.fail!(
            dgettext("content_transfer", "%{value1}: %{value2}",
              value1: hd(fields).destination.title,
              value2: inspect(Changeset.traverse_errors(cs, fn {message, _} -> message end))
            )
          )

      if Boundary.change(actor, :update, cs) != :ok,
        do:
          Error.fail!(
            dgettext(
              "content_transfer",
              "You do not have permission to change these fields or publish this entry."
            )
          )

      updated = Repo.update!(cs)
      Brando.EditSession.written(updated)
      Activity.imported(updated, actor, :update, label, Activity.changed_fields(cs))
      available
    end)
  end

  defp field_params(fields, bindings, actor) do
    entry = hd(fields).entry
    schema = entry.__struct__

    params =
      Map.new(fields, fn field ->
        join_schema = schema.__schema__(:association, field.field.association).related

        incoming =
          Portable.decode(field.source["blocks"], bindings, join_schema, actor_id!(actor))
          |> Enum.map(&adapt(&1, bindings))

        existing =
          if field.mode == "append",
            do: Enum.map(Map.fetch!(entry, field.field.association), &%{"id" => &1.id}),
            else: []

        incoming = Enum.with_index(incoming, fn block, n -> %{"sequence" => length(existing) + n, "block" => block} end)
        {to_string(field.field.association), existing ++ incoming}
      end)

    params
  end

  @doc """
  Builds the entry changeset that casts transferred block params, keeping the
  collection slots the params retain from module and slot validation.
  """
  def field_changeset(entry, params, actor) do
    entry.__struct__.changeset(entry, params, actor, nil,
      cast_blocks: true,
      retained_slot_uids: Brando.Content.Transfer.Ownership.retained_slots(params)
    )
  end

  @doc """
  Adds unsaved placeholder records with negative IDs for unbound media and gallery
  dependencies, so a preview can validate blocks before anything is created.
  """
  def preview_bindings(bundle, bindings) do
    bundle["dependencies"]
    |> Enum.with_index(1)
    |> Enum.reduce(bindings, fn {{token, dep}, n}, acc ->
      if Map.has_key?(acc, token) || dep["kind"] not in ~w(image file video gallery) do
        acc
      else
        Map.put(acc, token, placeholder_record(dep, n))
      end
    end)
  end

  defp placeholder_record(dep, n) do
    record = struct(Dependencies.schema!(dep["kind"]), id: -n)
    if dep["kind"] == "gallery", do: %{record | config_target: dep["config_target"]}, else: record
  end

  @doc """
  Fills a portable block and its children with the defaults of the bound module's
  current contract.
  """
  def adapt(block, bindings) do
    module_id = block["module_id"]

    module =
      Enum.find_value(bindings, fn
        {_, %Brando.Content.Module{id: id} = module} when id == module_id -> module
        _ -> nil
      end)

    block = if module, do: Contracts.defaults(block, module), else: block
    Map.update!(block, "children", &Enum.map(&1, fn child -> adapt(child, bindings) end))
  end

  @doc """
  Sets `module_version` on every new block changeset, including nested ones, from
  the module bound in `bindings`.
  """
  def stamp_versions(%Changeset{} = cs, bindings) do
    cs =
      if cs.data.__struct__ == Block && is_nil(cs.data.id) do
        stamp_module_version(cs, bindings)
      else
        cs
      end

    %{cs | changes: Map.new(cs.changes, fn {key, value} -> {key, stamp_versions(value, bindings)} end)}
  end

  def stamp_versions(list, bindings) when is_list(list), do: Enum.map(list, &stamp_versions(&1, bindings))
  def stamp_versions(value, _), do: value

  defp stamp_module_version(cs, bindings) do
    id = Changeset.get_field(cs, :module_id)

    module =
      Enum.find_value(bindings, fn {_, record} -> if match?(%Brando.Content.Module{id: ^id}, record), do: record end)

    if module, do: Changeset.put_change(cs, :module_version, module.version), else: cs
  end

  defp snapshot_fields(fields) do
    Map.new(fields, fn field ->
      joins = Map.fetch!(field.entry, field.field.association)

      {field.source["key"],
       %{
         "schema" => field.destination.schema,
         "id" => field.destination.id,
         "field" => field.field.name,
         "blocks" => Params.snapshot(joins),
         "contracts" =>
           joins
           |> Enum.map(&Params.snapshot(&1.block))
           |> Portable.walk(& &1["module_id"])
           |> Enum.reject(&is_nil/1)
           |> Enum.uniq()
           |> Map.new(fn id ->
             {to_string(id), Repo.get!(Brando.Content.Module, id) |> Contracts.capture()}
           end),
         "fingerprint" => Value.digest(Params.snapshot(joins))
       }}
    end)
  end

  def receipt(id, actor),
    do: Repo.one(from(r in Receipt, where: r.id == ^id and r.scope == ^scope() and r.actor_id == ^actor_id!(actor)))

  def history(actor) do
    ensure_scope!(actor)

    Repo.all(
      from(r in Receipt,
        where: r.scope == ^scope() and r.actor_id == ^actor_id!(actor),
        order_by: [desc: r.inserted_at],
        limit: 10
      )
    )
  end

  def retry_refresh(id, actor) do
    Error.protect(fn ->
      ensure_scope!(actor)

      receipt =
        receipt(id, actor) ||
          Error.fail!(dgettext("content_transfer", "This import is not available in the current workspace."))

      refresh_receipt(receipt, actor)
    end)
  end

  @doc """
  Re-renders the imported entries and queues processing for created images, then
  stores the per-item outcome on the receipt. A failed step is recorded as
  `"failed"` so the import can be retried with `retry_refresh/2`.
  """
  def refresh_receipt(receipt, actor) do
    media_results = Enum.map(receipt.mappings["created_images"] || [], &refresh_image(&1, actor))

    results =
      receipt.after
      |> Map.values()
      |> Enum.uniq_by(&{&1["schema"], &1["id"]})
      |> Enum.map(&refresh_entry(&1, receipt, actor))

    receipt |> Changeset.change(refresh: results ++ media_results) |> Repo.update!()
  end

  defp refresh_image(id, actor) do
    result =
      try do
        queue_image_refresh(id, actor)
      rescue
        # A post-commit refresh records any failure as a step the user can retry,
        # instead of crashing after the import has already been committed.
        # credo:disable-for-next-line ExSlop.Check.Warning.BlanketRescue
        _ -> :error
      end

    %{"kind" => "image", "id" => id, "status" => if(result == :ok, do: "queued", else: "failed")}
  end

  defp queue_image_refresh(id, actor) do
    image = Dependencies.load!("image", id, actor)

    if image.status == :processed || Brando.Images.Processing.processing_queued?(image) do
      :ok
    else
      case Brando.Images.Processing.queue_processing(image, actor, [], silent: true) do
        {:ok, _} -> :ok
        _ -> :error
      end
    end
  end

  defp refresh_entry(field, receipt, actor) do
    result =
      try do
        rerender_entry(field, receipt, actor)
      rescue
        # Rendering can raise from any template or block; see the media rescue above.
        # credo:disable-for-next-line ExSlop.Check.Warning.BlanketRescue
        _ -> {:error, :refresh_failed}
      end

    %{"schema" => field["schema"], "id" => field["id"], "status" => if(result == :ok, do: "complete", else: "failed")}
  end

  defp rerender_entry(field, receipt, actor) do
    schema = Brando.Content.Transfer.EntryCodec.schema!(field["schema"])
    entry = Repo.get(schema, field["id"])

    if receipt.restored_at && (is_nil(entry) || Map.get(entry, :deleted_at)) do
      :ok
    else
      render_and_cascade(schema, field, actor)
    end
  end

  defp render_and_cascade(schema, field, actor) do
    entry = Brando.Content.Transfer.EntryCodec.load!(field["schema"], field["id"], actor, :update)

    rendered =
      if Catalog.fields(schema) == [],
        do: {:ok, entry},
        else: Brando.Content.Blocks.render_entry(schema, entry.id)

    with {:ok, entry} <- rendered,
         {:ok, identifier} <- Brando.Content.update_identifier(entry.__struct__, entry),
         {:ok, _} <-
           Brando.Content.Blocks.enqueue_entry_cascade(
             entry.__struct__,
             entry,
             if(is_map(identifier), do: identifier.id)
           ),
         # Transfer writes past the Blueprint's after-save: a
         # synchronized source queues its translations' sync here,
         # and a synchronized translation its own recompute
         _ <- Brando.Translations.source_saved(entry),
         do: :ok
  end

  defp remembered_mappings(bundle, actor) do
    history(actor)
    |> Enum.reduce(%{}, fn receipt, acc ->
      if receipt.mappings["source"] == bundle["source"]["scope"] && !receipt.restored_at do
        Enum.reduce(bundle["dependencies"], acc, &remember_mapping(&1, &2, receipt))
      else
        acc
      end
    end)
  end

  defp remember_mapping({token, dep}, acc, receipt) do
    if dep["kind"] != "gallery" && get_in(receipt.mappings, ["requirements", token]) == Value.digest(dep),
      do: Map.put_new(acc, token, get_in(receipt.mappings, ["dependencies", token])),
      else: acc
  end

  @doc """
  Locks `FOR UPDATE` every persisted entry, its loaded associations and the bound
  records, in a stable order to avoid deadlocks. Fails when one has been removed.
  """
  def lock_records!(plan) do
    records = Enum.flat_map(plan.fields, fn field -> lockable(field.entry) end) ++ Map.values(plan.bindings)

    records
    |> Enum.filter(&(is_map(&1) && is_integer(Map.get(&1, :id)) && &1.id > 0))
    |> Enum.uniq_by(&{&1.__struct__, &1.id})
    |> Enum.sort_by(&{to_string(&1.__struct__), &1.id})
    |> Enum.each(fn record ->
      if record.__struct__.__schema__(:source) do
        Repo.one(from(r in record.__struct__, where: r.id == ^record.id, lock: "FOR UPDATE")) ||
          Error.fail!(dgettext("content_transfer", "Content was removed while applying. Review a new preview."))
      end
    end)
  end

  defp lockable(%Ecto.Association.NotLoaded{}), do: []

  defp lockable(%{__struct__: schema, id: _} = value) do
    if function_exported?(schema, :__schema__, 1) do
      [value | Enum.flat_map(schema.__schema__(:associations), fn key -> lockable(Map.get(value, key)) end)]
    else
      []
    end
  end

  defp lockable(values) when is_list(values), do: Enum.flat_map(values, &lockable/1)
  defp lockable(_), do: []

  def restore(id, actor), do: Brando.EditSession.collecting(fn -> protected_restore(id, actor) end)

  defp protected_restore(id, actor) do
    with {:ok, result} <- Error.protect(fn -> restore_in_transaction(id, actor) end) do
      case result do
        {:ok, receipt} -> {:ok, refresh_receipt(receipt, actor)}
        error -> error
      end
    end
  end

  defp restore_in_transaction(id, actor) do
    ensure_scope!(actor)
    Repo.transaction(fn -> restore_receipt!(id, actor) end)
  end

  defp restore_receipt!(id, actor) do
    Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "brando-content-transfer:" <> scope()
    ])

    receipt =
      Repo.one(
        from(r in Receipt,
          where: r.id == ^id and r.scope == ^scope() and r.actor_id == ^actor_id!(actor),
          lock: "FOR UPDATE"
        )
      ) || Error.fail!(dgettext("content_transfer", "This recovery snapshot is not available."))

    if receipt.restored_at,
      do: Error.fail!(dgettext("content_transfer", "This import has already been restored."))

    if receipt.mappings["version"] == 2 do
      Brando.Content.Transfer.Entries.restore!(receipt, actor)
    else
      Enum.each(receipt.after, &restore_field!(&1, receipt, actor))
    end

    receipt |> Changeset.change(restored_at: DateTime.utc_now()) |> Repo.update!()
  end

  defp restore_field!({key, expected}, receipt, actor) do
    entry = Catalog.load!(expected["schema"], expected["id"], actor, :update, lock: true)
    lock_records!(%{fields: [%{entry: entry}], bindings: %{}})
    entry = Catalog.load!(expected["schema"], expected["id"], actor, :update)
    field = Catalog.field!(entry.__struct__, expected["field"])
    current = Map.fetch!(entry, field.association) |> Params.snapshot()

    unless Value.digest(current) == expected["fingerprint"],
      do:
        Error.fail!(
          dgettext(
            "content_transfer",
            "Content changed after this import. Recovery would overwrite newer edits."
          )
        )

    before = receipt.before[key]["blocks"]
    # Restore from trusted local snapshots, allocating new owned identities.
    blocks = Enum.map(before, & &1["block"]) |> Brando.Content.Transfer.Recovery.copy()
    Brando.Content.Transfer.Recovery.validate_dependencies!(blocks, actor)
    bindings = recovery_bindings!(blocks, receipt.before[key]["contracts"], actor)
    lock_records!(%{fields: [], bindings: bindings})
    bindings = recovery_bindings!(blocks, receipt.before[key]["contracts"], actor)
    blocks = Enum.map(blocks, &adapt(&1, bindings))

    params = %{
      to_string(field.association) => Enum.with_index(blocks, fn block, n -> %{"sequence" => n, "block" => block} end)
    }

    {params, _} = Brando.Content.Transfer.Ownership.galleries(params, actor)
    cs = field_changeset(entry, params, actor) |> stamp_versions(bindings)

    if Boundary.change(actor, :update, cs) != :ok,
      do: Error.fail!(dgettext("content_transfer", "Recovery is no longer authorized."))

    updated = Repo.update!(cs)
    Brando.EditSession.written(updated)

    Activity.with_source(:import, fn ->
      Activity.with_batch(receipt.id, fn ->
        Activity.import_undone(updated, actor, :update)
      end)
    end)
  end

  def entry_fingerprint(entry), do: entry |> Params.snapshot() |> Value.digest()

  defp recovery_bindings!(blocks, contracts, actor) do
    blocks
    |> Portable.walk(fn block ->
      if id = block["module_id"] do
        module = Dependencies.load!("module", id, actor) |> Repo.preload([:refs, :vars])

        contract =
          contracts[to_string(id)] ||
            Error.fail!(dgettext("content_transfer", "The recovery module contract is unavailable."))

        Contracts.check!(block, contract, module)
        {"module:#{id}", module}
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  @doc """
  Fails unless the plan was previewed by this actor in the current site and environment.
  """
  def authorize_plan!(plan, actor) do
    unless plan.scope == scope() && plan.actor_id == actor_id!(actor),
      do: Error.fail!(dgettext("content_transfer", "This preview belongs to another actor, site or environment."))
  end

  defp actor_id!(%Brando.Authorization.Scope{user_id: id}) when is_integer(id), do: id
  defp actor_id!(%{id: id}) when is_integer(id), do: id
  defp actor_id!(_), do: Error.fail!(dgettext("content_transfer", "Content transfer requires an authenticated actor."))

  @doc """
  Fails unless the definition snapshot scope is active and the actor is an active
  account whose authorization scope matches the current tenant prefix.
  """
  def ensure_scope!(actor) do
    Snapshot.ensure_scope!()
    Brando.Content.Definitions.validate_actor!(actor)
    id = actor_id!(actor)
    actor_scope = Boundary.actor_scope(actor)

    unless actor_scope.user_id == id && (actor_scope.prefix || "public") == (Brando.Tenant.current_prefix() || "public"),
      do: Error.fail!(dgettext("content_transfer", "The actor does not belong to the selected site/environment."))
  end
end
