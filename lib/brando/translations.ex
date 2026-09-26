defmodule Brando.Translations do
  @moduledoc """
  Synchronized translation groups for `trait :translatable, mode: :synchronized`.

  A group has one source entry and any number of target entries, one per
  language. Targets are created on demand with `create_target/4`; the first
  entry of a group is its source until `transfer_source/3` moves the role.

  Saving the source (`source_saved/2`) enqueues `Brando.Worker.TranslationSync`,
  which computes a `Brando.Translations.PendingVersion` for every synchronized
  target (see `Brando.Translations.Sync`). The targets themselves are not
  written: published translations keep serving their content until an editor
  saves them with the pending version.

  `make_independent/3` takes one target out of synchronization. It keeps its
  content and its alternate link; its pending versions are superseded, not
  deleted.

  Groups are content, stored beside the entries in the current schema.
  """

  import Ecto.Query

  alias Brando.Content.Identifier
  alias Brando.Repo
  alias Brando.Translations.Group
  alias Brando.Translations.Member
  alias Brando.Translations.PendingVersion
  alias Brando.Translations.Sync
  alias Brando.Translations.WorkItem
  alias Brando.Utils
  alias Ecto.Changeset

  @doc "Whether `schema` declares `trait :translatable, mode: :synchronized`."
  def synchronized?(schema) when is_atom(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__translatable_config__, 0) and
      schema.__translatable_config__().mode == :synchronized
  end

  def synchronized?(_), do: false

  @doc """
  The translation state of a listing page, in one batch: for each entry of
  `entries` in a group, every language version of its group with its open
  work. Entries outside a group are left out.

      %{entry_id => [%{language: "en", entry_id: 7, role: :target,
                       synchronized: true, pending: true,
                       counts: %{translate: 2, review: 1}}, ...]}

  Only a member's current pending version counts; superseded ones are
  ignored, and a pending version with no open item still reads as pending
  — a structural or shared update without text work. With an `actor`, only
  versions the actor may read are listed.
  """
  def listing_status(schema, entries, actor \\ nil) do
    ids = for %{id: id} <- entries, id, do: id

    if ids == [] or not synchronized?(schema) do
      %{}
    else
      type = entry_type(schema)
      own = Repo.all(from m in Member, where: m.entry_type == ^type and m.entry_id in ^ids)
      group_ids = own |> Enum.map(& &1.group_id) |> Enum.uniq()
      members = Repo.all(from m in Member, where: m.group_id in ^group_ids, order_by: [asc: m.id])
      target_ids = for %Member{role: :target, synchronized: true, id: id} <- members, do: id

      versions =
        Repo.all(
          from v in PendingVersion,
            where: v.member_id in ^target_ids and v.status == :pending,
            select: {v.member_id, v.id}
        )

      version_ids = Enum.map(versions, &elem(&1, 1))

      counts =
        from(w in WorkItem,
          where: w.pending_version_id in ^version_ids and is_nil(w.resolved_at),
          group_by: [w.pending_version_id, w.kind],
          select: {w.pending_version_id, w.kind, count(w.id)}
        )
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0), fn {_, kind, count} -> {kind, count} end)
        |> Map.new(fn {version_id, kinds} -> {version_id, Map.new(kinds)} end)

      version_by_member = Map.new(versions)

      group_status =
        members
        |> Enum.group_by(& &1.group_id)
        |> Map.new(fn {group_id, group} ->
          {group_id,
           group
           |> Enum.sort_by(&(&1.role != :source))
           |> Enum.map(fn member ->
             version_id = version_by_member[member.id]

             %{
               language: member.language,
               entry_id: member.entry_id,
               role: member.role,
               synchronized: member.synchronized,
               pending: version_id != nil,
               counts: Map.get(counts, version_id, %{})
             }
           end)}
        end)

      visible = readable_ids(schema, Enum.map(members, & &1.entry_id), actor)

      Map.new(own, fn member ->
        {member.entry_id, Enum.filter(group_status[member.group_id], &MapSet.member?(visible, &1.entry_id))}
      end)
    end
  end

  defp readable_ids(_schema, ids, nil), do: MapSet.new(ids)

  defp readable_ids(schema, ids, actor) do
    from(e in schema, where: e.id in ^ids, select: e.id)
    |> Brando.Content.Transfer.Catalog.scoped_query(schema, actor, :read)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "The schema of a translation group's entries."
  def group_schema(group_id) do
    case Repo.get(Group, group_id) do
      nil -> nil
      group -> entry_schema(group)
    end
  end

  @doc """
  The languages of the entries `entry_id` is already linked to as alternates.
  Existing, independent alternates are not joined to a group, so no
  translation is created for their languages.
  """
  def alternate_languages(schema, entry_id) do
    if schema.has_alternates?() do
      from(a in Module.concat(schema, Alternate),
        join: e in ^schema,
        on: e.id == a.linked_entry_id,
        where: a.entry_id == ^entry_id,
        select: e.language
      )
      |> Repo.all()
      |> Enum.map(&to_string/1)
    else
      []
    end
  end

  @doc "Returns the group membership of an entry, or nil."
  def get_member(schema, entry_id) do
    Repo.one(from m in Member, where: m.entry_type == ^entry_type(schema) and m.entry_id == ^entry_id)
  end

  @doc "Returns all members of a group, source first."
  def list_members(group_id) do
    from(m in Member, where: m.group_id == ^group_id, order_by: [asc: m.id])
    |> Repo.all()
    |> Enum.sort_by(&(&1.role != :source))
  end

  @doc """
  Makes an entry the source of a new group.

  Refuses an entry that already belongs to a group, and schemas that are not
  synchronized.
  """
  def enroll_source(schema, entry_id, _actor) do
    with :ok <- ensure_synchronized(schema),
         {:ok, entry} <- load_entry(schema, entry_id),
         nil <- get_member(schema, entry_id) do
      Repo.transaction(fn ->
        group = Repo.insert!(%Group{entry_type: entry_type(schema)})

        Repo.insert!(%Member{
          group_id: group.id,
          entry_type: entry_type(schema),
          entry_id: entry.id,
          language: to_string(entry.language),
          role: :source,
          synchronized: true,
          last_synced_generation: group.source_generation
        })
      end)
    else
      %Member{} -> {:error, :already_enrolled}
      error -> error
    end
  end

  @doc """
  Creates the `language` translation of a synchronized source.

  The source is duplicated as an unpublished draft that keeps every block's
  sync identity, linked as an alternate and added to the group. An entry not
  yet in a group becomes its source.
  """
  def create_target(schema, source_id, language, actor) do
    language = to_string(language)

    with :ok <- ensure_language_known(schema, language),
         {:ok, source_member} <- source_member(schema, source_id, actor),
         :ok <- ensure_language_free(source_member, language) do
      Repo.transaction(fn ->
        case insert_target(schema, source_member, source_id, language, actor) do
          {:ok, target} -> target
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  defp insert_target(schema, source_member, source_id, language, actor) do
    with {:ok, target} <- duplicate_to_language(schema, source_id, language, actor),
         {:ok, source} <- load_entry(schema, source_id) do
      if schema.has_alternates?(), do: Module.concat(schema, Alternate).add(source_id, target.id)
      group = Repo.get!(Group, source_member.group_id)

      member =
        Repo.insert!(%Member{
          group_id: group.id,
          entry_type: entry_type(schema),
          entry_id: target.id,
          language: language,
          role: :target,
          synchronized: true,
          last_synced_generation: group.source_generation,
          baseline: Sync.baseline_for(source, schema, nil, module_uids([source], schema))
        })

      # The copy still links to the source language's content; its first
      # pending version points those links at this language's versions.
      sync_member(schema, source, member, group.source_generation, false)

      {:ok, target}
    end
  end

  @doc """
  Stops synchronizing one target.

  Its content, pending edits and alternate link stay; structure and shared
  fields become editable. Pending versions are marked superseded. The source
  cannot be made independent — transfer the role first.
  """
  def make_independent(schema, entry_id, _actor) do
    case get_member(schema, entry_id) do
      nil ->
        {:error, :not_enrolled}

      %Member{role: :source} ->
        {:error, :is_source}

      %Member{synchronized: false} = member ->
        {:ok, member}

      member ->
        Repo.transaction(fn ->
          supersede_pending(member.id)

          member
          |> Changeset.change(synchronized: false, detached_at: now())
          |> Repo.update!()
        end)
    end
  end

  @doc """
  Makes a synchronized target the source of its group.

  The former source becomes a synchronized target. Every member's baseline is
  reset to the new source, so the switch itself raises no review work; the next
  source save synchronizes structure from the new source.
  """
  def transfer_source(schema, new_source_id, _actor) do
    with %Member{role: :target, synchronized: true} = new_source <- get_member(schema, new_source_id),
         {:ok, entry} <- load_entry(schema, new_source_id) do
      baseline = Sync.baseline_for(entry, schema, nil, module_uids([entry], schema))

      Repo.transaction(fn ->
        from(m in Member, where: m.group_id == ^new_source.group_id and m.role == :source)
        |> Repo.update_all(set: [role: :target, synchronized: true, updated_at: naive_now()])

        from(m in Member, where: m.group_id == ^new_source.group_id)
        |> Repo.update_all(set: [baseline: baseline, updated_at: naive_now()])

        supersede_pending(new_source.id)

        new_source
        |> Changeset.change(role: :source, baseline: %{})
        |> Repo.update!()
      end)
    else
      nil -> {:error, :not_enrolled}
      %Member{} -> {:error, :not_a_synchronized_target}
      error -> error
    end
  end

  @doc """
  Called after an entry is saved. When it is the source of a group with
  synchronized targets, enqueues their synchronization.

  `minor: true` marks a save of minor text corrections: changed source text
  raises no review work.
  """
  def source_saved(%schema{id: id}, opts \\ []) do
    with true <- synchronized?(schema),
         %Member{} = member <- get_member(schema, id) do
      case member do
        %Member{role: :source, group_id: group_id} -> enqueue_sync(group_id, Keyword.get(opts, :minor, false))
        # A saved translation gets its pending version recomputed against what
        # was saved, so applying it later keeps the new text.
        %Member{role: :target, synchronized: true} -> enqueue_resync(member)
        _ -> :ok
      end
    else
      _ -> :ok
    end
  end

  defp enqueue_sync(group_id, minor?) do
    %{group_id: group_id, minor: minor?}
    |> Brando.Tenant.Job.attach()
    |> Brando.Worker.TranslationSync.new()
    |> Oban.insert()
  end

  defp enqueue_resync(%Member{group_id: group_id, id: member_id}) do
    %{group_id: group_id, member_id: member_id}
    |> Brando.Tenant.Job.attach()
    |> Brando.Worker.TranslationSync.new()
    |> Oban.insert()
  end

  @doc """
  Recomputes one synchronized target's pending version against its saved
  content, at the group's current source generation. Unresolved work carries
  over; nothing new is asked for review.
  """
  def resync_target(group_id, member_id) do
    Repo.transaction(fn ->
      group = Repo.one!(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE")

      with %Member{role: :target, synchronized: true} = member <- Repo.get(Member, member_id),
           {:ok, source} <- load_group_source(group) do
        sync_member(entry_schema(group), source, member, group.source_generation, false)
      else
        _ -> :skipped
      end
    end)
  end

  ## Editing a synchronized target

  @doc """
  What the editor needs to open a synchronized target: its membership, the
  source entry's id and language, and the current pending version with its
  work items (or nil). Returns nil for entries outside a group.
  """
  def editor_state(schema, entry_id) do
    with true <- synchronized?(schema),
         %Member{} = member <- get_member(schema, entry_id) do
      source = Enum.find(list_members(member.group_id), &(&1.role == :source))
      pending = if member.role == :target and member.synchronized, do: current_pending(member.id)

      %{
        member: member,
        source: source && %{id: source.entry_id, language: source.language},
        pending: pending
      }
    else
      _ -> nil
    end
  end

  @doc """
  Called by the editor after it saved a synchronized target.

  `review` describes what the editor worked from: `%{version_id: id,
  acknowledged: [path]}`, the pending version it loaded and the paths whose
  text it marked as reviewed without changing. Only work of that version is
  resolved, matched by path and the source text it was raised against, so
  work raised by a newer source save stays open:

    * `:translate` and `:review` — when the saved text differs from the
      pending text, or the path was acknowledged
    * `:shared_update` — when the saved value is the source's
    * `:awaiting_translation` — never; it resolves when the link can be made

  The pending version is then recomputed against the saved content, carrying
  unresolved work. Returns `{:ok, %{open: count, stale: boolean}}`; `stale`
  means the source was saved again after the loaded version was computed.
  """
  def target_saved(schema, entry_id, review \\ nil) do
    with true <- synchronized?(schema),
         %Member{role: :target, synchronized: true} = member <- get_member(schema, entry_id) do
      Repo.transaction(fn -> save_target(schema, member, review) end)
    else
      _ -> {:ok, %{open: 0, stale: false}}
    end
  end

  # Under the group's lock: resolve what the review completed, then recompute
  # the pending version against the saved translation.
  defp save_target(schema, member, review) do
    group = Repo.one!(from g in Group, where: g.id == ^member.group_id, lock: "FOR UPDATE")
    current = current_pending(member.id)
    reviewed = reviewed_version(member, review)

    previous =
      case {current, reviewed} do
        {nil, _} -> nil
        {current, nil} -> current
        {current, reviewed} -> resolve_reviewed(schema, member, current, reviewed, review)
      end

    case load_group_source(group) do
      {:ok, source} -> sync_member(schema, source, member, group.source_generation, false, previous)
      :error -> :ok
    end

    %{open: open_count(member.id), stale: reviewed != nil and reviewed.source_generation < group.source_generation}
  end

  @doc """
  Checks a synchronized translation's save before it is written, and returns
  the changeset to save.

  Structure, media, links and source-controlled values of a synchronized
  translation follow its source. Whatever path changed them — a disabled
  control, a forged event, a replayed parameter — the save is compared with
  the version the editor worked from: the pending version `version_id`, or
  the saved translation when none was loaded. Any difference refuses the
  save with the paths that differ: `{:error, {:source_controlled, paths}}`.

  New blocks and table rows keep the sync identity the pending version gave
  them, which the form does not carry.

  Entries outside a group, sources and independent translations pass through.
  """
  def check_target_save(schema, entry_id, %Changeset{} = changeset, version_id \\ nil) do
    with true <- synchronized?(schema),
         %Member{role: :target, synchronized: true} = member <- get_member(schema, entry_id) do
      reference =
        case reviewed_version(member, %{version_id: version_id}) do
          nil ->
            {:ok, saved} = load_entry(schema, entry_id)
            saved

          version ->
            decode_payload(version)
        end

      changeset = restore_sync_identities(changeset, schema, reference)
      submitted = Changeset.apply_changes(changeset)
      module_uids = module_uids([reference, submitted], schema)
      expected = Sync.owned_rows(reference, schema, nil, module_uids)
      actual = Sync.owned_rows(submitted, schema, nil, module_uids)

      case (expected -- actual) ++ (actual -- expected) do
        [] -> {:ok, changeset}
        differing -> {:error, {:source_controlled, paths(differing)}}
      end
    else
      _ -> {:ok, changeset}
    end
  end

  defp paths(rows), do: rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  # A block the pending version added is new to the form, which gives it a
  # fresh `sync_uid`; put back the one the source assigned, found by `uid`.
  defp restore_sync_identities(changeset, schema, reference) do
    blocks = reference_blocks(reference, schema)

    Enum.reduce(blocks_fields(schema), changeset, fn field, changeset ->
      case Changeset.get_change(changeset, field) do
        joins when is_list(joins) ->
          Changeset.put_change(changeset, field, Enum.map(joins, &restore_join(&1, blocks)))

        _ ->
          changeset
      end
    end)
  end

  defp restore_join(%Changeset{} = join, blocks) do
    case Changeset.get_change(join, :block) do
      %Changeset{} = block -> Changeset.put_change(join, :block, restore_block(block, blocks))
      _ -> join
    end
  end

  defp restore_join(join, _blocks), do: join

  defp restore_block(%Changeset{} = block, blocks) do
    reference = blocks[Changeset.get_field(block, :uid)]

    block
    |> restore_block_identity(reference)
    |> restore_table_rows(reference)
    |> restore_children(blocks)
  end

  defp restore_block_identity(%Changeset{data: %{id: nil}} = block, %{sync_uid: sync_uid}),
    do: Changeset.force_change(block, :sync_uid, sync_uid)

  defp restore_block_identity(block, _reference), do: block

  # New table rows take the identity of the pending version's row at the same
  # position: they were restored from it in order.
  defp restore_table_rows(block, nil), do: block

  defp restore_table_rows(block, reference) do
    case Changeset.get_change(block, :table_rows) do
      rows when is_list(rows) ->
        reference_rows = loaded_list(reference.table_rows)

        rows =
          rows
          |> Enum.with_index()
          |> Enum.map(fn {row, index} -> restore_row_identity(row, Enum.at(reference_rows, index)) end)

        Changeset.put_change(block, :table_rows, rows)

      _ ->
        block
    end
  end

  defp restore_row_identity(%Changeset{data: %{id: nil}} = row, %{sync_uid: sync_uid}) when not is_nil(sync_uid),
    do: Changeset.force_change(row, :sync_uid, sync_uid)

  defp restore_row_identity(row, _reference), do: row

  defp restore_children(block, blocks) do
    case Changeset.get_change(block, :children) do
      children when is_list(children) ->
        Changeset.put_change(block, :children, Enum.map(children, &restore_child(&1, blocks)))

      _ ->
        block
    end
  end

  defp restore_child(%Changeset{} = child, blocks), do: restore_block(child, blocks)
  defp restore_child(child, _blocks), do: child

  defp reference_blocks(entry, schema) do
    blocks_fields(schema)
    |> Enum.flat_map(&loaded_list(Map.get(entry, &1)))
    |> Enum.flat_map(&walk_blocks(&1.block))
    |> Map.new(&{&1.uid, &1})
  end

  defp walk_blocks(nil), do: []
  defp walk_blocks(block), do: [block | Enum.flat_map(loaded_list(block.children), &walk_blocks/1)]

  defp blocks_fields(schema) do
    if function_exported?(schema, :__blocks_fields__, 0),
      do: Enum.map(schema.__blocks_fields__(), &:"entry_#{&1.name}"),
      else: []
  end

  defp loaded_list(list) when is_list(list), do: list
  defp loaded_list(_), do: []

  defp open_count(member_id) do
    case current_pending(member_id) do
      nil -> 0
      version -> Enum.count(version.work_items, &is_nil(&1.resolved_at))
    end
  end

  defp reviewed_version(_member, nil), do: nil

  defp reviewed_version(member, review) do
    with id when not is_nil(id) <- review[:version_id],
         %PendingVersion{member_id: member_id} = version when member_id == member.id <-
           Repo.get(PendingVersion, id) |> Repo.preload(:work_items) do
      version
    else
      _ -> nil
    end
  end

  # Resolves the current version's work that the reviewed version also held
  # and the save completed, then marks the current version applied. Returns it,
  # so the recomputation carries what is still open.
  defp resolve_reviewed(schema, member, current, reviewed, review) do
    {:ok, saved} = load_entry(schema, member.entry_id)
    payload = decode_payload(reviewed)
    module_uids = module_uids([saved, payload], schema)
    saved_rows = rows_by_path(saved, schema, module_uids)
    reviewed_rows = rows_by_path(payload, schema, module_uids)
    reviewed_work = MapSet.new(reviewed.work_items, &{&1.path, &1.source_digest})
    acknowledged = MapSet.new(List.wrap(review[:acknowledged]))
    timestamp = now()

    items =
      Enum.map(current.work_items, fn item ->
        if is_nil(item.resolved_at) and MapSet.member?(reviewed_work, {item.path, item.source_digest}) and
             done?(item, saved_rows, reviewed_rows, acknowledged) do
          item
          |> Changeset.change(resolved_at: timestamp, resolved_generation: reviewed.source_generation)
          |> Repo.update!()
        else
          item
        end
      end)

    current
    |> Changeset.change(status: :applied, applied_at: timestamp)
    |> Repo.update!()
    |> Map.put(:work_items, items)
  end

  defp done?(%WorkItem{kind: kind, path: path}, saved, reviewed, acknowledged) when kind in [:translate, :review] do
    MapSet.member?(acknowledged, path) or
      (Map.has_key?(saved, path) and not blank?(saved[path]) and saved[path] != reviewed[path])
  end

  defp done?(%WorkItem{kind: :shared_update, path: path, source_digest: digest}, saved, _reviewed, _acknowledged),
    do: Map.has_key?(saved, path) and Sync.digest(saved[path]) == digest

  defp done?(_item, _saved, _reviewed, _acknowledged), do: false

  defp rows_by_path(entry, schema, module_uids),
    do: Map.new(Sync.flatten_entry(entry, schema, nil, module_uids), fn {path, _, value} -> {path, value} end)

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false

  defp load_group_source(group) do
    case Repo.one(from m in Member, where: m.group_id == ^group.id and m.role == :source) do
      nil -> :error
      member -> load_entry(entry_schema(group), member.entry_id)
    end
  end

  defp entry_schema(group), do: String.to_existing_atom(group.entry_type)

  @doc """
  Synchronizes every synchronized target of a group from its source.

  Runs under a lock on the group, so concurrent source saves are applied in
  order, and bumps the group's `source_generation`.
  """
  def sync_group(group_id, opts \\ []) do
    minor? = Keyword.get(opts, :minor, false)

    Repo.transaction(fn ->
      group = Repo.one!(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE")
      schema = String.to_existing_atom(group.entry_type)
      generation = group.source_generation + 1

      group |> Changeset.change(source_generation: generation) |> Repo.update!()

      case sync_members(schema, list_members(group.id), generation, minor?) do
        {:ok, results} -> results
        :error -> Repo.rollback(:source_not_found)
      end
    end)
  end

  defp sync_members(schema, members, generation, minor?) do
    source_member = Enum.find(members, &(&1.role == :source))

    case source_member && load_entry(schema, source_member.entry_id) do
      {:ok, source} ->
        {:ok,
         for member <- members, member.role == :target, member.synchronized do
           sync_member(schema, source, member, generation, minor?)
         end}

      _ ->
        :error
    end
  end

  defp sync_member(schema, source, member, generation, minor?, previous \\ :current) do
    case load_entry(schema, member.entry_id) do
      {:ok, target} ->
        result =
          Sync.compute_pending(source, target, member.baseline,
            schema: schema,
            module_uids: module_uids([source, target], schema),
            minor: minor?,
            identifiers: identifier_map(source, schema, member.language)
          )

        previous = if previous == :current, do: current_pending(member.id), else: previous
        record_pending(member, result, previous, generation, schema)

        member
        |> Changeset.change(baseline: result.baseline, last_synced_generation: generation)
        |> Repo.update!()

        {member.id, :ok}

      _ ->
        {member.id, :target_not_found}
    end
  end

  @doc """
  Maps every identifier `source` links to onto the identifier of the same
  content in `language`: itself when it is already in that language or has
  none, its alternate in that language, or nil when there is no such version.
  """
  def identifier_map(source, schema, language) do
    ids = Sync.identifier_ids(source, schema)

    from(i in Identifier, where: i.id in ^ids)
    |> Repo.all()
    |> Map.new(&{&1.id, counterpart_id(&1, language)})
  end

  defp counterpart_id(%Identifier{language: identifier_language} = identifier, language) do
    if identifier_language in [nil, ""] or to_string(identifier_language) == language,
      do: identifier.id,
      else: alternate_identifier_id(identifier, language)
  end

  defp alternate_identifier_id(%Identifier{schema: module, entry_id: entry_id}, language) do
    with true <- alternates?(module),
         true <- language in Enum.map(Ecto.Enum.values(module, :language), &to_string/1),
         alternate_id when not is_nil(alternate_id) <- alternate_entry_id(module, entry_id, language) do
      identifier_id_for(module, alternate_id)
    else
      _ -> nil
    end
  end

  defp alternates?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :has_alternates?, 0) and module.has_alternates?()
  end

  defp alternate_entry_id(module, entry_id, language) do
    query =
      from a in Module.concat(module, Alternate),
        join: e in ^module,
        on: e.id == a.linked_entry_id,
        where: a.entry_id == ^entry_id and e.language == ^language,
        select: e.id,
        limit: 1

    query =
      if :deleted_at in module.__schema__(:fields),
        do: from([_a, e] in query, where: is_nil(e.deleted_at)),
        else: query

    Repo.one(query)
  end

  defp identifier_id_for(module, entry_id) do
    case Repo.one(from i in Identifier, where: i.schema == ^module and i.entry_id == ^entry_id, select: i.id) do
      nil -> create_identifier_id(module, entry_id)
      id -> id
    end
  end

  defp create_identifier_id(module, entry_id) do
    with %{} = entry <- Repo.get(module, entry_id),
         {:ok, %Identifier{id: id}} <- Brando.Content.create_identifier(module, entry) do
      id
    else
      _ -> nil
    end
  end

  @doc """
  Called when two entries are linked as alternates. Groups waiting for a
  translation of either entry — an `:awaiting_translation` item on a pending
  version — are synchronized again so the link can be filled in.
  """
  def alternate_added(module, entry_id, linked_entry_id) do
    identifier_ids =
      Repo.all(
        from i in Identifier,
          where: i.schema == ^module and i.entry_id in ^[entry_id, linked_entry_id],
          select: i.id
      )

    patterns = Enum.flat_map(identifier_ids, &["%/identifiers/#{&1}", "%/identifier/#{&1}"])

    if patterns != [] do
      matches = Enum.reduce(patterns, dynamic(false), &dynamic([w], ^&2 or like(w.path, ^&1)))

      from(w in WorkItem,
        join: v in assoc(w, :pending_version),
        join: m in assoc(v, :member),
        where: w.kind == :awaiting_translation and v.status == :pending and is_nil(w.resolved_at),
        where: ^matches,
        distinct: true,
        select: m.group_id
      )
      |> Repo.all()
      |> Enum.each(&enqueue_sync(&1, false))
    end

    :ok
  end

  @doc """
  Replaces a member's pending version with `result`.

  Unresolved work items of the previous version are carried over when their
  path still exists and the new computation did not raise its own item for it.
  Nothing is recorded when the result changes nothing and no work carries over.
  """
  def record_pending(member, result, previous, generation, schema) do
    new_paths = MapSet.new(result.work_items, & &1.path)

    carried =
      case previous do
        nil ->
          []

        %PendingVersion{work_items: items} ->
          for item <- items,
              is_nil(item.resolved_at),
              MapSet.member?(result.paths, item.path),
              not MapSet.member?(new_paths, item.path),
              do: Map.take(item, [:path, :kind, :source_digest, :minor])
      end

    if previous, do: supersede_pending(member.id)

    if result.changed? or carried != [] do
      version =
        Repo.insert!(%PendingVersion{
          member_id: member.id,
          source_generation: generation,
          source_fingerprint: result.source_fingerprint,
          base_fingerprint: result.base_fingerprint,
          schema_version: schema_version(schema),
          payload: Utils.term_to_binary(result.payload),
          notes: result.notes,
          status: :pending
        })

      timestamp = naive_now()

      items =
        Enum.map(result.work_items ++ carried, fn item ->
          Map.merge(item, %{pending_version_id: version.id, inserted_at: timestamp, updated_at: timestamp})
        end)

      Repo.insert_all(WorkItem, items)
      version
    end
  end

  @doc "Returns the pending version of an entry with its work items, or nil."
  def get_pending_version(schema, entry_id) do
    case get_member(schema, entry_id) do
      nil -> nil
      member -> current_pending(member.id)
    end
  end

  @doc "Decodes a pending version's payload into the entry struct."
  def decode_payload(%PendingVersion{payload: payload}), do: :erlang.binary_to_term(payload, [:safe])

  @doc """
  Refuses to delete the source of a group that still has synchronized targets.
  """
  def guard_delete(module, %{id: id}) do
    with true <- synchronized?(module),
         %Member{role: :source, group_id: group_id} <- get_member(module, id),
         true <-
           exists?(from m in Member, where: m.group_id == ^group_id and m.role == :target and m.synchronized == true) do
      {:error, :group_has_synchronized_members}
    else
      _ -> :ok
    end
  end

  def guard_delete(_, _), do: :ok

  @doc """
  Maps the `{module_origin, module_id}` of every block in `entries` to its
  module's `uid`, for module-variable selectors. Empty when the schema
  controls no module variables.
  """
  def module_uids(entries, schema) do
    if schema.__translatable_config__() |> Map.get(:source_controlled_module_vars, %{}) |> map_size() == 0 do
      %{}
    else
      refs = Sync.module_refs(entries, schema)
      local_ids = for {:local, id} <- refs, do: id

      local =
        from(m in Brando.Content.Module, where: m.id in ^local_ids, select: {m.id, m.uid})
        |> Repo.all()
        |> Map.new(fn {id, uid} -> {{:local, id}, uid} end)

      shared =
        for {:shared, id} <- refs, module = Brando.Content.fetch_module(id, :shared), into: %{} do
          {{:shared, id}, module.uid}
        end

      Map.merge(local, shared)
    end
  end

  @doc """
  Checks the module-variable selectors of a synchronized schema against the
  modules in the database. Returns `[]`, or problems such as
  `{:unknown_module, uid}` and `{:unknown_var, uid, key}` — a module that was
  renamed, deleted or never imported, or a variable it does not define.
  Checked here rather than at compile time because modules are content.
  """
  def check_config(schema, config \\ nil) do
    config = config || schema.__translatable_config__()
    selectors = Map.get(config, :source_controlled_module_vars, %{})

    Enum.flat_map(selectors, fn {uid, keys} -> check_module(uid, keys) end)
  end

  defp check_module(uid, keys) do
    case Repo.one(from m in Brando.Content.Module, where: m.uid == ^uid and is_nil(m.deleted_at), preload: :vars) do
      nil -> [{:unknown_module, uid}]
      module -> for key <- keys, key not in Enum.map(module.vars || [], & &1.key), do: {:unknown_var, uid, key}
    end
  end

  defp entry_type(schema), do: to_string(schema)

  @doc "The current pending version of a member, with its work items, or nil."
  def current_pending_for_member(member_id), do: current_pending(member_id)

  defp current_pending(member_id) do
    Repo.one(
      from v in PendingVersion,
        where: v.member_id == ^member_id and v.status == :pending,
        preload: [:work_items]
    )
  end

  defp supersede_pending(member_id) do
    from(v in PendingVersion, where: v.member_id == ^member_id and v.status == :pending)
    |> Repo.update_all(set: [status: :superseded, updated_at: naive_now()])
  end

  defp source_member(schema, source_id, actor) do
    case get_member(schema, source_id) do
      nil ->
        enroll_source(schema, source_id, actor)

      %Member{role: :source} = member ->
        {:ok, member}

      %Member{} ->
        {:error, :not_source}
    end
  end

  defp ensure_language_free(%Member{group_id: group_id}, language) do
    if exists?(from m in Member, where: m.group_id == ^group_id and m.language == ^language),
      do: {:error, :language_exists},
      else: :ok
  end

  defp ensure_language_known(schema, language) do
    if language in Enum.map(Ecto.Enum.values(schema, :language), &to_string/1),
      do: :ok,
      else: {:error, :unknown_language}
  end

  defp ensure_synchronized(schema) do
    if synchronized?(schema), do: :ok, else: {:error, :not_synchronized}
  end

  defp duplicate_to_language(schema, source_id, language, actor) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context

    slug_fields =
      Enum.map(schema.__slug_fields__(), fn %{name: name} ->
        {name, fn _entry, value -> Utils.slugify("#{value}-#{language}") end}
      end)

    override_opts = [
      change_fields: [{:language, String.to_existing_atom(language)} | slug_fields],
      merge_change_fields: true,
      keep_sync_uid: true
    ]

    apply(context, :"duplicate_#{singular}", [source_id, actor, override_opts])
  end

  defp load_entry(schema, id) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context
    apply(context, :"get_#{singular}", [%{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(schema)}])
  end

  defp schema_version(schema) do
    if function_exported?(schema, :__schema_version__, 0), do: schema.__schema_version__(), else: 0
  end

  defp exists?(query), do: Repo.one(from(q in query, select: true, limit: 1)) == true

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
  defp naive_now, do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
end
