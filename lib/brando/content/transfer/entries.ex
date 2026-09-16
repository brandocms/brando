defmodule Brando.Content.Transfer.Entries do
  @moduledoc false
  import Ecto.Query, only: [from: 2]
  alias Brando.Authorization.Boundary
  alias Brando.Content.Definition.Value
  alias Brando.Content.Transfer

  alias Brando.Content.Transfer.{
    Catalog,
    Contracts,
    Dependencies,
    EntryCodec,
    Error,
    Media,
    Ownership,
    Portable,
    Receipt,
    Requirements
  }

  alias Brando.Drafts.Params
  alias Brando.Repo
  alias Ecto.Changeset

  def take!(selectors, actor, opts) do
    Enum.uniq_by(selectors, &{&1.schema, &1.id})
    |> Enum.map_reduce(Dependencies.new(actor, opts), fn selector, state ->
      entry = EntryCodec.load!(selector.schema, selector.id, actor, :export)
      description = Catalog.describe(entry)
      {data, state} = EntryCodec.encode(entry, state)

      {%{
         "key" => description.key,
         "schema" => description.schema,
         "title" => description.title,
         "language" => description.language,
         "hints" => description.hints,
         "data" => data
       }, state}
    end)
  end

  def fields(entries) do
    Enum.flat_map(entries, fn entry ->
      Enum.map(Enum.sort(entry["data"]["blocks"]), fn {name, blocks} ->
        entry
        |> Map.take(~w(schema title language hints))
        |> Map.merge(%{
          "key" => entry["key"] <> ":" <> name,
          "entry_key" => entry["key"],
          "field" => name,
          "blocks" => blocks,
          "fingerprint" => Value.digest(blocks)
        })
      end)
    end)
  end

  def validate!(bundle) do
    entries = bundle["entries"]
    unless is_list(entries) && length(entries) in 1..100, do: Error.fail!("An entry bundle must contain 1–100 entries.")

    Enum.each(entries, fn entry ->
      Value.keys!(entry, ~w(key schema title language hints data), "entry")
      Enum.each(~w(key schema title), &Value.nonempty!(entry[&1], "entry #{&1}"))
      unless is_map(entry["hints"]) && is_binary(entry["language"]), do: Error.fail!("Invalid entry matching hints.")
      EntryCodec.validate!(entry["data"], EntryCodec.schema!(entry["schema"]), bundle["dependencies"])
      uids = entry["data"] |> EntryCodec.block_fields() |> List.flatten() |> Portable.walk(& &1["uid"])
      Value.unique!(uids, "entry block UIDs")
      if length(uids) > 5_000, do: Error.fail!("An entry exceeds 5,000 blocks.")
    end)

    Value.unique!(Enum.map(entries, & &1["key"]), "entries")

    Enum.each(bundle["dependencies"], fn {_, dep} ->
      if entry = Enum.find(entries, &(&1["key"] == dep["entry_key"])) do
        unless dep["kind"] in ~w(entry identifier fragment) && dep["schema"] == entry["schema"],
          do: Error.fail!("An included relationship points to an incompatible entry type.")
      end
    end)

    unless fields(entries) == bundle["fields"], do: Error.fail!("The entry and field manifests disagree.")
    :ok
  end

  def preview!(archive, targets, actor, opts) do
    Transfer.ensure_scope!(actor)
    bundle = Portable.validate!(archive.bundle)
    operation_id = Keyword.get(opts, :operation_id, Ecto.UUID.generate())
    unless match?({:ok, _}, Ecto.UUID.cast(operation_id)), do: Error.fail!("Invalid import operation ID.")
    supplied = Keyword.get(opts, :dependencies, %{})

    entries =
      Enum.with_index(bundle["entries"], 1)
      |> Enum.map(fn {source, n} ->
        candidates =
          case Error.protect(fn -> Catalog.candidates(source, actor) end) do
            {:ok, candidates} -> candidates
            _ -> []
          end

        base = %{
          source: source,
          candidates: candidates,
          issue: nil,
          destination: nil,
          before: nil,
          mode: get_in(targets, [source["key"], "mode"]) || "create",
          entry: nil,
          params: nil,
          changes: [],
          status: nil,
          unique_keys: [],
          incoming_count: source["data"] |> EntryCodec.block_fields() |> List.flatten() |> Portable.count()
        }

        case Error.protect(fn ->
               schema = EntryCodec.schema!(source["schema"])
               target = targets[source["key"]] || %{}
               mode = target["mode"] || "create"
               unless mode in ~w(create update), do: Error.fail!("Choose Create new or Update existing.")

               entry =
                 if mode == "update",
                   do: EntryCodec.load!(schema, target["id"], actor, :update),
                   else: EntryCodec.blank(schema)

               Catalog.authorize!(
                 actor,
                 if(mode == "create", do: :create, else: :update),
                 if(mode == "create", do: schema, else: entry)
               )

               overrides = target["attributes"] || %{}
               Value.keys!(overrides, editable(source), "entry overrides")
               data = put_in(source["data"]["attributes"], Map.merge(source["data"]["attributes"], overrides))["data"]
               publication = target["publication"] || if(mode == "create", do: "draft", else: "preserve")
               unless publication in ~w(draft preserve source), do: Error.fail!("Choose how to publish this entry.")

               data =
                 if Map.has_key?(data["attributes"], "status") do
                   status =
                     case publication do
                       "draft" -> "draft"
                       "preserve" -> to_string(Map.get(entry, :status) || :draft)
                       "source" -> source["data"]["attributes"]["status"]
                     end

                   put_in(data["attributes"]["status"], status)
                 else
                   data
                 end

               data =
                 if Map.has_key?(data["attributes"], "publish_at") do
                   date =
                     case publication do
                       "draft" -> nil
                       "preserve" -> Params.snapshot(Map.get(entry, :publish_at))
                       "source" -> data["attributes"]["publish_at"]
                     end

                   put_in(data["attributes"]["publish_at"], date)
                 else
                   data
                 end

               stub =
                 Enum.reduce(data["attributes"], %{entry | id: entry.id || -n}, fn {key, value}, acc ->
                   field = Enum.find(EntryCodec.attributes(schema), &(to_string(&1) == key))

                   case Ecto.Type.cast(schema.__schema__(:type, field), value) do
                     {:ok, cast} -> Map.put(acc, field, cast)
                     _ -> acc
                   end
                 end)

               Map.merge(base, %{
                 mode: mode,
                 entry: entry,
                 data: data,
                 stub: stub,
                 destination: Catalog.describe(stub),
                 before: if(mode == "update", do: EntryCodec.fingerprint(entry))
               })
             end) do
          {:ok, item} -> item
          {:error, message} -> %{base | issue: message}
        end
      end)

    bundled = bundled_bindings(bundle, entries, supplied, :preview)
    {dependencies, bindings} = Transfer.resolve_dependencies(bundle, supplied, archive.files, actor, bundled)
    preview_bindings = Transfer.preview_bindings(bundle, bindings)

    entries =
      Enum.map(entries, fn
        %{issue: nil} = item ->
          case Error.protect(fn ->
                 validate_contracts!(item.data, bundle, bindings)
                 params = EntryCodec.decode(item.data, item.entry.__struct__, preview_bindings, actor)
                 cs = changeset!(item, params, actor)

                 %{
                   item
                   | params: params,
                     changes: changes(item, cs),
                     status: Changeset.get_field(cs, :status),
                     unique_keys: unique_keys(cs)
                 }
               end) do
            {:ok, checked} -> checked
            {:error, message} -> %{item | issue: message}
          end

        item ->
          item
      end)

    destinations = for %{mode: "update", destination: %{key: key}} <- entries, do: key
    issues = for item <- entries ++ dependencies, item.issue, do: item.issue
    keys = Enum.flat_map(entries, & &1.unique_keys)

    issues =
      if length(keys) != length(Enum.uniq(keys)),
        do: ["Two incoming entries use the same unique key. Choose distinct values before importing." | issues],
        else: issues

    issues =
      if length(destinations) != length(Enum.uniq(destinations)),
        do: ["Two entries point to the same destination. Choose distinct destinations." | issues],
        else: issues

    issues =
      case Error.protect(fn -> ordered(entries, bundle, supplied) end) do
        {:error, message} -> [message | issues]
        _ -> issues
      end

    fingerprint =
      Value.digest(%{
        "scope" => Transfer.scope(),
        "bundle" => bundle,
        "targets" => targets,
        "supplied" => supplied,
        "entries" => Enum.map(entries, &Map.take(&1, [:mode, :before, :issue, :status])),
        "dependencies" => Enum.map(dependencies, &Map.take(&1, [:token, :id, :fingerprint, :action, :issue]))
      })

    %{
      id: operation_id,
      actor_id: actor_id(actor),
      scope: Transfer.scope(),
      archive: archive,
      targets: targets,
      supplied: supplied,
      entries: entries,
      fields: [],
      dependencies: dependencies,
      bindings: bindings,
      problems: Enum.uniq(issues),
      fingerprint: fingerprint
    }
  end

  def editable(source),
    do:
      Enum.filter(~w(title name uri slug key parent_key language), fn key ->
        attrs = source["data"]["attributes"]
        Map.has_key?(attrs, key) && (is_nil(attrs[key]) || is_binary(attrs[key]))
      end)

  defp changes(item, cs) do
    Enum.map(Enum.sort(item.data["attributes"]), fn {key, incoming} ->
      field = Enum.find(EntryCodec.attributes(item.entry.__struct__), &(to_string(&1) == key))

      %{
        field: key,
        before: Params.snapshot(Map.get(item.entry, field)),
        after: Params.snapshot(Changeset.get_field(cs, field)),
        incoming: incoming
      }
    end)
    |> Enum.filter(&if item.mode == "create", do: &1.after not in [nil, "", [], %{}], else: &1.before != &1.after)
    |> Enum.sort_by(fn change ->
      {Enum.find_index(
         ~w(title name uri slug key language status publish_at meta_title meta_description),
         &(&1 == change.field)
       ) || 99, change.field}
    end)
  end

  defp changeset!(item, params, actor) do
    cs = Transfer.field_changeset(item.entry, params, actor) |> Brando.Publisher.maybe_override_status()

    unless cs.valid?,
      do: Error.fail!("Entry validation: #{inspect(Changeset.traverse_errors(cs, fn {message, _} -> message end))}")

    unique!(cs)

    if Boundary.change(actor, if(item.mode == "create", do: :create, else: :update), cs) != :ok,
      do: Error.fail!("You do not have permission to save or publish this entry.")

    cs
  end

  # Collision callbacks normally rename a key during insertion. A transfer must
  # review the actual key, so catch those collisions before any write occurs.
  defp unique!(cs) do
    schema = cs.data.__struct__

    Enum.each(Brando.Blueprint.Attributes.__attributes__(schema), fn attribute ->
      unique = attribute.opts[:unique]

      if unique && Changeset.get_field(cs, attribute.name) do
        scope =
          if unique == true,
            do: [],
            else: Brando.Blueprint.UniqueFields.scope(unique, Keyword.get(unique, :prevent_collision))

        fields = [attribute.name | scope]

        query =
          Enum.reduce(fields, schema, fn field, query ->
            value = Changeset.get_field(cs, field)

            if is_nil(value),
              do: from(e in query, where: false),
              else: from(e in query, where: field(e, ^field) == ^value)
          end)

        query = if cs.data.id, do: from(e in query, where: e.id != ^cs.data.id), else: query

        if Repo.one(from(e in query, select: e.id, limit: 1)),
          do:
            Error.fail!(
              "#{Phoenix.Naming.humanize(attribute.name)} is already in use. Update the matching entry or choose another value."
            )
      end
    end)
  end

  defp unique_keys(cs) do
    schema = cs.data.__struct__

    for attribute <- Brando.Blueprint.Attributes.__attributes__(schema),
        unique = attribute.opts[:unique],
        fields = Brando.Blueprint.UniqueFields.fields(attribute.name, unique),
        values = Enum.map(fields, &Changeset.get_field(cs, &1)),
        Enum.all?(values, &(!is_nil(&1))),
        do: {schema, fields, values}
  end

  defp validate_contracts!(data, bundle, bindings) do
    data
    |> EntryCodec.block_fields()
    |> List.flatten()
    |> Portable.walk(fn block ->
      if token = block["module_id"] do
        module = bindings[token] || Error.fail!("Resolve the required modules before reviewing content.")
        dep = bundle["dependencies"][token]
        Contracts.check!(block, dep["contract"], module)

        if dep["parent"] && bindings[dep["parent"]] && module.parent_id != bindings[dep["parent"]].id,
          do: Error.fail!("The child module belongs to a different destination parent.")

        if dep["table_template"] && bindings[dep["table_template"]] &&
             module.table_template_id != bindings[dep["table_template"]].id,
           do: Error.fail!("Map the table template used by the destination module.")
      end
    end)
  end

  defp bundled_bindings(bundle, entries, supplied, phase) do
    by_key = Map.new(Enum.filter(entries, &(&1.issue == nil)), &{&1.source["key"], &1})

    Enum.reduce(bundle["dependencies"], %{}, fn {token, dep}, acc ->
      item = by_key[dep["entry_key"]]

      if item && supplied[token] in [nil, "bundle"] do
        entry = if phase in [:preview, :reserve], do: item.stub, else: item.entry

        record =
          if dep["kind"] == "identifier" do
            if phase == :preview do
              identifier = entry.__struct__.__identifier__(entry)

              existing =
                if entry.id > 0, do: Repo.get_by(Brando.Content.Identifier, schema: entry.__struct__, entry_id: entry.id)

              %{identifier | id: if(existing, do: existing.id, else: entry.id)}
            else
              generated = entry.__struct__.__identifier__(entry)
              existing = Repo.get_by(Brando.Content.Identifier, schema: entry.__struct__, entry_id: entry.id)

              result =
                if existing,
                  do: {:ok, %{generated | id: existing.id}},
                  else: Brando.Content.create_identifier(entry.__struct__, entry)

              case result do
                {:ok, %Brando.Content.Identifier{} = identifier} -> identifier
                _ -> Error.fail!("The included entry does not support content links.")
              end
            end
          else
            entry
          end

        Map.put(acc, token, record)
      else
        acc
      end
    end)
  end

  defp ordered(entries, bundle, supplied) do
    keys = MapSet.new(entries, & &1.source["key"])

    pending =
      Enum.map(entries, fn item ->
        refs = Requirements.references(item.source["data"], bundle["dependencies"])

        required =
          for token <- refs,
              supplied[token] in [nil, "bundle"],
              key = bundle["dependencies"][token]["entry_key"],
              MapSet.member?(keys, key),
              key != item.source["key"],
              bundle["dependencies"][token]["kind"] != "identifier",
              do: key

        {item, MapSet.new(required)}
      end)

    # Existing records already have stable identities, including self-links.
    available = MapSet.new(Enum.filter(entries, &(&1.mode == "update" && &1.destination)), & &1.source["key"])
    sort(pending, available, [])
  end

  defp sort([], _, result), do: result

  defp sort(pending, available, result) do
    {ready, remaining} = Enum.split_with(pending, fn {_, needs} -> MapSet.subset?(needs, available) end)

    if ready == [],
      do:
        Error.fail!(
          "New entries refer to each other in a cycle. Map one of those references to an existing entry, then review again."
        )

    items = Enum.map(ready, &elem(&1, 0))
    sort(remaining, Enum.reduce(items, available, &MapSet.put(&2, &1.source["key"])), result ++ items)
  end

  def apply!(plan, actor) do
    Transfer.ensure_scope!(actor)
    Transfer.authorize_plan!(plan, actor)
    unless Transfer.applicable?(plan), do: Error.fail!("Resolve every blocking problem before importing.")

    case Transfer.receipt(plan.id, actor) do
      %Receipt{} = receipt -> {:ok, receipt}
      nil -> apply_new!(plan, actor)
    end
  end

  defp apply_new!(plan, actor) do
    media =
      for %{action: :create, token: token, dependency: %{"kind" => kind} = dep} <- plan.dependencies,
          kind in ~w(image file),
          into: %{},
          do: {token, dep}

    stage = Media.stage!(media, plan.archive.files, actor, plan.id)

    result =
      try do
        Repo.transaction(fn ->
          Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
            "brando-content-transfer:" <> Transfer.scope()
          ])

          if receipt = Transfer.receipt(plan.id, actor) do
            receipt
          else
            Transfer.lock_records!(%{fields: plan.entries, bindings: plan.bindings})
            current = preview!(plan.archive, plan.targets, actor, dependencies: plan.supplied, operation_id: plan.id)

            unless current.fingerprint == plan.fingerprint && Transfer.applicable?(current),
              do: Error.fail!("The destination changed after preview. Review the import again.")

            before =
              Enum.map(current.entries, fn item ->
                snapshot =
                  if item.mode == "update" do
                    {[source], state} = take!([%{schema: item.entry.__struct__, id: item.entry.id}], actor, media: false)

                    %{
                      "entry" => source,
                      "dependencies" => state.dependencies,
                      "id" => item.entry.id,
                      "schema" => to_string(item.entry.__struct__)
                    }
                  else
                    %{"created" => true}
                  end

                {item.source["key"], snapshot}
              end)
              |> Map.new()

            bindings = Transfer.persist_dependencies!(current, stage, actor)
            {saved, bindings} = persist!(current, bindings, actor)

            after_entries =
              Map.new(saved, fn item ->
                entry = EntryCodec.load!(item.entry.__struct__, item.entry.id, actor)

                {item.source["key"],
                 %{
                   "schema" => to_string(entry.__struct__),
                   "id" => entry.id,
                   "title" => Catalog.describe(entry).title,
                   "fingerprint" => EntryCodec.fingerprint(entry)
                 }}
              end)

            Repo.insert!(%Receipt{
              id: plan.id,
              package_id: plan.archive.bundle["id"],
              fingerprint: plan.fingerprint,
              scope: Transfer.scope(),
              actor_id: actor_id(actor),
              before: before,
              after: after_entries,
              mappings: %{
                "version" => 2,
                "source" => plan.archive.bundle["source"]["scope"],
                "targets" => plan.targets,
                "created_order" => Enum.map(Enum.filter(saved, &(&1.mode == "create")), & &1.source["key"]),
                "dependencies" => Map.new(bindings, fn {token, record} -> {token, record.id} end),
                "requirements" =>
                  Map.new(plan.archive.bundle["dependencies"], fn {token, dep} -> {token, Value.digest(dep)} end),
                "created_images" =>
                  for(
                    %{action: :create, token: token, dependency: %{"kind" => "image"}} <- current.dependencies,
                    do: bindings[token].id
                  ),
                "transferred_media" =>
                  for(
                    %{action: :create, token: token, dependency: %{"kind" => kind} = dep} <- current.dependencies,
                    kind in ~w(image file),
                    do: %{"kind" => kind, "id" => bindings[token].id, "sha256" => dep["original"]["sha256"]}
                  )
              }
            })
          end
        end)
      rescue
        error ->
          Media.cleanup(stage, false)
          reraise error, __STACKTRACE__
      end

    Media.cleanup(stage, match?({:ok, _}, result))

    case result do
      {:ok, receipt} -> {:ok, Transfer.refresh_receipt(receipt, actor)}
      error -> error
    end
  end

  defp persist!(plan, bindings, actor) do
    # Replace preview placeholders for existing bundled destinations first.
    existing = Enum.filter(plan.entries, &(&1.mode == "update"))
    bindings = Map.merge(bindings, bundled_bindings(plan.archive.bundle, existing, plan.supplied, :preview))
    # Allocate destination identities inside the transaction before creating
    # their polymorphic identifiers. This supports self-links and mutual entry
    # selections without inserting incomplete entry records.
    reserved =
      for item <- plan.entries, item.mode == "create" do
        schema = item.entry.__struct__
        prefix = schema.__schema__(:prefix) || Brando.Tenant.current_prefix() || "public"

        table =
          Enum.map_join([prefix, schema.__schema__(:source)], ".", &("\"" <> String.replace(&1, "\"", "\"\"") <> "\""))

        %{rows: [[id]]} =
          Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT nextval(pg_get_serial_sequence($1, 'id'))", [table])

        unless is_integer(id), do: Error.fail!("This Blueprint needs a generated integer entry ID.")
        %{item | stub: %{item.stub | id: id}}
      end

    reserved_ids = Map.new(reserved, &{&1.source["key"], &1.stub.id})
    bindings = Map.merge(bindings, bundled_bindings(plan.archive.bundle, reserved, plan.supplied, :reserve))
    available = MapSet.new(for {_, %Brando.Galleries.Gallery{id: id}} <- bindings, do: id)

    {saved, {bindings, _}} =
      Enum.map_reduce(ordered(plan.entries, plan.archive.bundle, plan.supplied), {bindings, available}, fn item,
                                                                                                           {bindings,
                                                                                                            available} ->
        validate_contracts!(item.data, plan.archive.bundle, bindings)
        params = EntryCodec.decode(item.data, item.entry.__struct__, bindings, actor)
        {params, available} = Ownership.galleries(params, actor, available)
        cs = changeset!(item, params, actor) |> Transfer.stamp_versions(bindings)
        {cs, available} = claim_galleries(cs, item.data, bindings, actor, available)
        cs = if item.mode == "create", do: Changeset.put_change(cs, :id, reserved_ids[item.source["key"]]), else: cs
        entry = if item.mode == "create", do: Repo.insert!(cs), else: Repo.update!(cs)

        if is_nil(Repo.get_by(Brando.Content.Identifier, schema: entry.__struct__, entry_id: entry.id)),
          do: Brando.Content.create_identifier(entry.__struct__, entry)

        if Map.has_key?(cs.changes, :publish_at) do
          cancel_status_jobs(entry)
          {:ok, _} = Brando.Publisher.schedule_publishing(entry, cs, actor)
        end

        saved = %{item | entry: EntryCodec.preload(entry)}
        bindings = Map.merge(bindings, bundled_bindings(plan.archive.bundle, [saved], plan.supplied, :persist))
        {saved, {bindings, available}}
      end)

    {saved, bindings}
  end

  defp claim_galleries(cs, node, bindings, actor, available) do
    schema = cs.data.__struct__

    {cs, available} =
      Enum.reduce(EntryCodec.references(schema), {cs, available}, fn
        {name, Brando.Galleries.Gallery, _, _}, {cs, available} ->
          token = node["references"][to_string(name)]

          if EntryCodec.gallery_asset?(schema, name) && token do
            gallery = bindings[token]
            {params, available} = Ownership.galleries(%{"gallery_id" => gallery.id}, actor, available)
            gallery = Repo.get!(Brando.Galleries.Gallery, params["gallery_id"])
            {Changeset.put_assoc(cs, name, gallery), available}
          else
            {cs, available}
          end

        _, acc ->
          acc
      end)

    Enum.reduce(EntryCodec.owned(schema), {cs, available}, fn {name, _, _}, {cs, available} ->
      value = Map.get(cs.changes, name)
      nodes = List.wrap(node["owned"][to_string(name)])

      if value do
        # Replacement changesets also contain old children marked for deletion.
        {children, {available, _}} =
          Enum.map_reduce(List.wrap(value), {available, nodes}, fn child, {available, remaining} ->
            if child.action in [:replace, :delete] do
              {child, {available, remaining}}
            else
              [node | rest] = remaining
              {child, available} = claim_galleries(child, node, bindings, actor, available)
              {child, {available, rest}}
            end
          end)

        updated = if is_list(value), do: children, else: List.first(children)
        {%{cs | changes: Map.put(cs.changes, name, updated)}, available}
      else
        {cs, available}
      end
    end)
  end

  def restore!(receipt, actor) do
    current =
      Map.new(receipt.after, fn {key, expected} ->
        entry = EntryCodec.load!(expected["schema"], expected["id"], actor, :update, lock: true)
        Transfer.lock_records!(%{fields: [%{entry: entry}], bindings: %{}})
        entry = EntryCodec.load!(expected["schema"], expected["id"], actor)

        unless EntryCodec.fingerprint(entry) == expected["fingerprint"],
          do: Error.fail!("Content changed after this import. Recovery would overwrite newer edits.")

        {key, entry}
      end)

    Enum.each(receipt.before, fn {key, snapshot} ->
      unless snapshot["created"] do
        source = snapshot["entry"]

        bundle = %{
          "format" => "brando-content",
          "version" => 2,
          "id" => Ecto.UUID.generate(),
          "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
          "source" => %{"scope" => Transfer.scope(), "label" => "Recovery"},
          "entries" => [source],
          "fields" => fields([source]),
          "definitions" => nil,
          "dependencies" => snapshot["dependencies"]
        }

        mappings =
          Map.new(bundle["dependencies"], fn {token, dep} ->
            {token, if(dep["kind"] == "gallery", do: "create", else: dep["source_id"])}
          end)

        targets = %{source["key"] => %{"mode" => "update", "id" => current[key].id, "publication" => "source"}}
        plan = preview!(%{bundle: bundle, files: %{}}, targets, actor, dependencies: mappings)
        unless Transfer.applicable?(plan), do: Error.fail!("Recovery needs attention: " <> Enum.join(plan.problems, " "))
        Transfer.lock_records!(%{fields: plan.entries, bindings: plan.bindings})
        bindings = Transfer.persist_dependencies!(plan, %{items: %{}}, actor)
        persist!(plan, bindings, actor)
      end
    end)

    created = Enum.map(receipt.mappings["created_order"] || [], &current[&1])
    ensure_unused!(created)
    # Undo creation in reverse dependency order. These rows were created by
    # this operation and have passed the full-entry edit check above.
    Enum.each(Enum.reverse(receipt.mappings["created_order"] || []), fn key ->
      entry = current[key]
      Catalog.authorize!(actor, :delete, entry)
      if Map.get(entry, :status) == :published, do: Catalog.authorize!(actor, :publish, entry)
      cancel_status_jobs(entry)
      delete_owned!(entry)
    end)

    # Delete identifiers after all owned selections. Their FK cascades must not
    # remove another created entry's selections before that entry is recovered.
    Enum.each(created, &Brando.Content.delete_identifier(&1.__struct__, &1))
  end

  defp delete_owned!(entry) do
    schema = entry.__struct__

    {before, after_entry} =
      EntryCodec.owned(schema)
      |> Enum.filter(fn {name, _, _} -> name in schema.__schema__(:associations) end)
      |> Enum.split_with(fn {name, _, _} ->
        !match?(%Ecto.Association.BelongsTo{}, schema.__schema__(:association, name))
      end)

    Enum.each(before, fn {name, _, _} -> Enum.each(List.wrap(Map.get(entry, name)), &delete_owned!/1) end)
    Repo.delete!(entry)
    Enum.each(after_entry, fn {name, _, _} -> Enum.each(List.wrap(Map.get(entry, name)), &delete_owned!/1) end)
  end

  defp cancel_status_jobs(entry) do
    args = Brando.Tenant.Job.attach(%{schema: to_string(entry.__struct__), id: entry.id, status: "published"})

    Repo.delete_all(
      from(j in Oban.Job, where: j.worker == "Brando.Worker.EntryPublisher" and fragment("? @> ?", j.args, ^args))
    )
  end

  defp ensure_unused!([]), do: :ok

  defp ensure_unused!(created) do
    prefix = Brando.Tenant.current_prefix() || "public"

    columns =
      Ecto.Adapters.SQL.query!(
        Repo.repo(),
        "SELECT table_schema, table_name, column_name FROM information_schema.columns WHERE table_schema = ANY($1)",
        [Enum.uniq([prefix, "public"])]
      )
      |> Map.fetch!(:rows)
      |> Enum.group_by(fn [prefix, table, _] -> {prefix, table} end, fn [_, _, column] -> column end)

    has_column? = fn schema, name ->
      key = {schema.__schema__(:prefix) || prefix, schema.__schema__(:source)}
      to_string(schema.__schema__(:field_source, name) || name) in (columns[key] || [])
    end

    owned = created |> Enum.flat_map(&EntryCodec.records/1) |> Enum.filter(&(Map.get(&1, :id) != nil))
    allowed = Enum.group_by(owned, & &1.__struct__, & &1.id)

    identifiers =
      Enum.flat_map(created, fn entry ->
        case Repo.get_by(Brando.Content.Identifier, schema: entry.__struct__, entry_id: entry.id) do
          nil -> []
          identifier -> [identifier]
        end
      end)

    schemas =
      (Brando.Authorization.Catalog.schemas() ++ Enum.map(owned, & &1.__struct__))
      |> then(fn schemas ->
        schemas ++ Enum.flat_map(schemas, fn schema -> Enum.map(EntryCodec.owned(schema), &elem(&1, 1)) end)
      end)
      |> Enum.uniq()
      |> Enum.filter(&(function_exported?(&1, :__schema__, 1) && is_binary(&1.__schema__(:source))))

    Enum.each(created ++ identifiers, fn target ->
      Enum.each(schemas, fn schema ->
        Enum.each(schema.__schema__(:associations), fn name ->
          case schema.__schema__(:association, name) do
            %Ecto.Association.BelongsTo{related: related, owner_key: key} when related == target.__struct__ ->
              ids = allowed[schema] || []
              query = from(e in schema, where: field(e, ^key) == ^target.id, select: 1, limit: 1)
              query = if :id in schema.__schema__(:fields), do: from(e in query, where: e.id not in ^ids), else: query
              if has_column?.(schema, key) && Repo.one(query), do: used!()

            _ ->
              :ok
          end
        end)
      end)
    end)

    Enum.each(identifiers, fn identifier ->
      outside_blocks =
        Brando.Content.Blocks.list_block_ids_with_identifier_in_refs(identifier.id) --
          (allowed[Brando.Content.Block] || [])

      if outside_blocks != [], do: used!()

      for schema <- Catalog.entry_schemas(),
          attribute <- Brando.Blueprint.Attributes.__attributes__(schema),
          attribute.type in [:text, :string],
          attribute.name in schema.__schema__(:fields),
          has_column?.(schema, attribute.name) do
        ids = allowed[schema] || []

        query =
          from(e in schema,
            where: e.id not in ^ids and ilike(field(e, ^attribute.name), "%data-identifier-id%"),
            select: field(e, ^attribute.name)
          )

        if Enum.any?(Repo.all(query), &Brando.RichText.contains_identifier?(&1, identifier.id)), do: used!()
      end
    end)
  end

  defp used!,
    do:
      Error.fail!(
        "Other content now references an entry created by this import. Remove those references before recovering."
      )

  defp actor_id(%Brando.Authorization.Scope{user_id: id}), do: id
  defp actor_id(%{id: id}), do: id
end
