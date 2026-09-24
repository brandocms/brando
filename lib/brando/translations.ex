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

  @doc "Whether `schema` declares `trait :translatable, mode: :synchronized`."
  def synchronized?(schema) when is_atom(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__translatable_config__, 0) and
      schema.__translatable_config__().mode == :synchronized
  end

  def synchronized?(_), do: false

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
          baseline: Sync.baseline_for(source, schema)
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
          |> Ecto.Changeset.change(synchronized: false, detached_at: now())
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
      baseline = Sync.baseline_for(entry, schema)

      Repo.transaction(fn ->
        from(m in Member, where: m.group_id == ^new_source.group_id and m.role == :source)
        |> Repo.update_all(set: [role: :target, synchronized: true, updated_at: naive_now()])

        from(m in Member, where: m.group_id == ^new_source.group_id)
        |> Repo.update_all(set: [baseline: baseline, updated_at: naive_now()])

        supersede_pending(new_source.id)

        new_source
        |> Ecto.Changeset.change(role: :source, baseline: %{})
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
         %Member{role: :source, group_id: group_id} <- get_member(schema, id) do
      enqueue_sync(group_id, Keyword.get(opts, :minor, false))
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

      group |> Ecto.Changeset.change(source_generation: generation) |> Repo.update!()

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

  defp sync_member(schema, source, member, generation, minor?) do
    case load_entry(schema, member.entry_id) do
      {:ok, target} ->
        result =
          Sync.compute_pending(source, target, member.baseline,
            schema: schema,
            minor: minor?,
            identifiers: identifier_map(source, schema, member.language)
          )

        previous = current_pending(member.id)
        record_pending(member, result, previous, generation, schema)

        member
        |> Ecto.Changeset.change(baseline: result.baseline, last_synced_generation: generation)
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

  defp entry_type(schema), do: to_string(schema)

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
