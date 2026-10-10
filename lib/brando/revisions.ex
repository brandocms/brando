defmodule Brando.Revisions do
  @moduledoc """
  Stores immutable snapshots for schemas using `Brando.Trait.Revisioned` and
  restores them through the same derived-state boundaries as ordinary updates.

  Revision capture is deliberately synchronous. A background job that only
  carries an entry id cannot know which saved state it was created for once a
  later save has committed.
  """

  use Brando.Query

  import Ecto.Query

  alias Brando.Cache
  alias Brando.Content
  alias Brando.Query
  alias Brando.Repo
  alias Brando.Revisions.Revision
  alias Brando.Utils

  @type changeset :: Ecto.Changeset.t()
  @type revision :: Brando.Revisions.Revision.t()
  @type revision_active :: boolean
  @type user :: Brando.Users.User.t() | :system

  @metadata_fields [
    :active,
    :creator_id,
    :description,
    :entry_id,
    :entry_type,
    :inserted_at,
    :metadata,
    :protected,
    :revision,
    :scheduled,
    :schema_version,
    :updated_at
  ]

  query :list, Revision do
    fn query -> from(q in query) end
  end

  filters Revision do
    fn
      {:entry_id, entry_id}, query ->
        from q in query, where: q.entry_id == ^entry_id

      {:entry_type, entry_type}, query when is_binary(entry_type) ->
        entry_type = entry_type |> List.wrap() |> Module.concat() |> to_string()
        from q in query, where: q.entry_type == ^entry_type

      {:entry_type, entry_type}, query when is_atom(entry_type) ->
        entry_type = to_string(entry_type)
        from q in query, where: q.entry_type == ^entry_type

      {:revision, revision}, query ->
        from q in query, where: q.revision == ^revision

      {:active, active}, query ->
        from q in query, where: q.active == ^active
    end
  end

  @doc """
  List revision metadata without loading snapshot blobs.

  Results are newest first. `:limit` defaults to 50 and is capped at 200;
  `:offset` defaults to zero.
  """
  @spec list_revision_metadata(module(), integer() | binary(), keyword()) :: {:ok, [revision()]}
  def list_revision_metadata(entry_type, entry_id, opts \\ []) do
    entry_type_binary = to_string(entry_type)
    entry_id = normalize_entry_id(entry_id)
    limit = opts |> Keyword.get(:limit, 50) |> min(200) |> max(1)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    revisions =
      Revision
      |> where([r], r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id)
      |> order_by([r], desc: r.revision)
      |> limit(^limit)
      |> offset(^offset)
      |> select([r], struct(r, ^@metadata_fields))
      |> Brando.Authorization.Boundary.subject_query(entry_type, entry_id)
      |> preload(creator: :avatar)
      |> Repo.all()

    {:ok, revisions}
  end

  @doc """
  Create an immutable snapshot from the supplied entry state.

  Loaded associations are preserved exactly as supplied. Missing associations
  are preloaded without reloading scalar fields, which allows callers to store
  a validated, unsaved form state intentionally.
  """
  @spec create_revision(map(), user(), revision_active()) :: {:ok, revision()} | {:error, term()}
  def create_revision(entry, user, set_active \\ true)

  def create_revision(%{__struct__: entry_type, id: entry_id} = entry, user, set_active)
      when not is_nil(entry_id) do
    entry_type_binary = to_string(entry_type)
    user_id = user_id(user)

    Repo.transaction(fn ->
      lock_entry!(entry_type, entry_id)

      if set_active do
        deactivate_all_revisions(entry_type_binary, entry_id)
      end

      snapshot = snapshot_entry(entry_type, entry)

      attrs = %{
        active: set_active,
        creator_id: user_id,
        encoded_entry: Utils.term_to_binary(snapshot),
        entry_id: entry_id,
        entry_type: entry_type_binary,
        metadata: %{},
        protected: false,
        revision: next_revision(entry_type_binary, entry_id),
        scheduled: false,
        schema_version: Brando.Blueprint.Snapshot.get_current_version(entry_type)
      }

      case Repo.insert(Revision.changeset(%Revision{}, attrs)) do
        {:ok, revision} -> revision
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def create_revision(%{id: nil}, _user, _set_active), do: {:error, {:entry, :not_persisted}}

  @doc "Set the human-readable description for a revision."
  def describe_revision(entry_type, entry_id, revision_number, description) do
    entry_type_binary = to_string(entry_type)
    entry_id = normalize_entry_id(entry_id)
    revision_number = normalize_revision_number(revision_number)

    from(r in Revision,
      where:
        r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id and
          r.revision == ^revision_number,
      update: [set: [description: ^description]]
    )
    |> Brando.Authorization.Boundary.subject_query(entry_type, entry_id, :update)
    |> Repo.update_all([])
  end

  @doc "Mark or unmark a revision as protected."
  def protect_revision(entry_type, entry_id, revision_number, protect) when is_boolean(protect) do
    entry_type_binary = to_string(entry_type)
    entry_id = normalize_entry_id(entry_id)
    revision_number = normalize_revision_number(revision_number)

    from(r in Revision,
      where:
        r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id and
          r.revision == ^revision_number,
      update: [set: [protected: ^protect]]
    )
    |> Brando.Authorization.Boundary.subject_query(entry_type, entry_id, :update)
    |> Repo.update_all([])
  end

  @doc "Mark a revision as having a pending publishing job."
  def mark_revision_scheduled(entry_type, entry_id, revision_number, true) do
    entry_type_binary = to_string(entry_type)
    entry_id = normalize_entry_id(entry_id)
    revision_number = normalize_revision_number(revision_number)

    from(r in Revision,
      where:
        r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id and
          r.revision == ^revision_number and r.active == false,
      update: [set: [scheduled: true]]
    )
    |> Brando.Authorization.Boundary.subject_query(entry_type, entry_id, :schedule)
    |> Repo.update_all([])
  end

  def mark_revision_scheduled(entry_type, entry_id, revision_number, scheduled) when is_boolean(scheduled) do
    entry_type_binary = to_string(entry_type)
    entry_id = normalize_entry_id(entry_id)
    revision_number = normalize_revision_number(revision_number)

    from(r in Revision,
      where:
        r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id and
          r.revision == ^revision_number,
      update: [set: [scheduled: ^scheduled]]
    )
    |> Brando.Authorization.Boundary.subject_query(entry_type, entry_id, :schedule)
    |> Repo.update_all([])
  end

  @doc """
  Create an inactive revision by applying params to a historical snapshot.
  """
  def create_from_base_revision(entry_schema, base_revision_version, entry_id, entry_params, user) do
    with {:ok, {_revision, {_revision_id, decoded_entry}}} <-
           get_revision(entry_schema, entry_id, base_revision_version),
         changeset <- entry_schema.changeset(decoded_entry, entry_params, user, nil, cast_blocks: true),
         :ok <- Brando.Authorization.Boundary.change(user, :update, changeset),
         {:ok, updated_entry} <- Ecto.Changeset.apply_action(changeset, :update) do
      create_revision(updated_entry, user, false)
    end
  end

  @doc "Purge inactive, unprotected, unscheduled revisions older than 30 days."
  def purge_revisions do
    from(r in Revision,
      where:
        fragment("? < current_timestamp - interval '30 day'", r.inserted_at) and
          r.protected == false and r.scheduled == false and r.active == false
    )
    |> Repo.delete_all()
  end

  @doc "Purge inactive, unprotected, unscheduled revisions for an entry."
  def purge_revisions(entry_type, entry_id) do
    entry_type_binary = to_string(entry_type)
    entry_id = normalize_entry_id(entry_id)

    from(r in Revision,
      where:
        r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id and
          r.protected == false and r.scheduled == false and r.active == false
    )
    |> Brando.Authorization.Boundary.subject_query(entry_type, entry_id, :delete)
    |> Repo.delete_all()
  end

  @doc "Delete one inactive, unprotected, unscheduled revision."
  def delete_revision(entry_type, entry_id, revision_number) do
    entry_type_binary = to_string(entry_type)
    entry_id = normalize_entry_id(entry_id)
    revision_number = normalize_revision_number(revision_number)

    from(r in Revision,
      where:
        r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id and
          r.revision == ^revision_number and r.active == false and
          r.protected == false and r.scheduled == false
    )
    |> Brando.Authorization.Boundary.subject_query(entry_type, entry_id, :delete)
    |> Repo.delete_all()
  end

  @doc """
  Drops the schedule of `revision`, which scheduled publishing refused to
  publish because the entry was in the trash (`{:error, :in_trash}` from
  `set_entry_to_revision/5`), and notes it in Activity. Done under the
  entry's lock and only while `still_current?.()` (the refused job is still
  the revision's schedule): a new schedule made in between is left alone. A
  restore in between changes nothing: the revision was refused, and without
  this its schedule would have no job.
  """
  def drop_schedule_in_trash(entry_schema, entry_id, revision_number, user, still_current?) do
    Repo.transaction(fn ->
      lock_entry!(entry_schema, entry_id)

      if still_current?.() do
        entry = Repo.get!(entry_schema, entry_id)
        mark_revision_scheduled(entry_schema, entry_id, revision_number, false)
        Brando.Activity.scheduled_revision_in_trash(entry, user, revision_number)
      end
    end)

    :ok
  end

  @doc "Delete all revision history for a permanently deleted entry."
  def delete_entry_revisions(entry_type, entry_id) do
    entry_id = normalize_entry_id(entry_id)
    Brando.Publisher.cancel_revision_jobs(entry_type, entry_id)
    entry_type_binary = to_string(entry_type)

    from(r in Revision, where: r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id)
    |> Repo.delete_all()
  end

  @doc "Get and decode the newest revision for an entry."
  def get_last_revision(entry_type, entry_id) do
    entry_type
    |> revision_query(entry_id)
    |> order_by([r], desc: r.revision)
    |> limit(1)
    |> fetch_and_decode()
  end

  @doc "Get and decode the active revision for an entry."
  def get_active_revision(entry_type, entry_id) do
    entry_type
    |> revision_query(entry_id)
    |> where([r], r.active == true)
    |> limit(1)
    |> fetch_and_decode()
  end

  @doc """
  Restore an entry to a revision.

  The restore is transactional, includes block associations, refreshes the
  content identifier, and atomically moves the active marker. Pass
  `publish?: true` when a scheduled job executes to force published status and
  the current publication timestamp; it returns `{:error, :in_trash}`, changing
  nothing, for an entry in the trash. A restore never moves the entry into or
  out of the trash.
  """
  def set_entry_to_revision(entry_schema, entry_id, revision_number, user, opts \\ []) do
    Brando.Authorization.Boundary.run(user, :restore, entry_schema, fn user ->
      do_set_entry_to_revision(entry_schema, entry_id, revision_number, user, opts)
    end)
  end

  defp do_set_entry_to_revision(entry_schema, entry_id, revision_number, user, opts) do
    entry_id = normalize_entry_id(entry_id)
    revision_number = normalize_revision_number(revision_number)
    publish? = Keyword.get(opts, :publish?, false)

    result =
      Repo.transaction(fn ->
        lock_entry!(entry_schema, entry_id)

        revision = get_revision_record!(entry_schema, entry_id, revision_number)
        cancel_pending_activation!(entry_schema, entry_id, revision_number, publish?)
        target_entry = decode_revision!(revision)
        restore_missing_block_links!(entry_schema, entry_id, target_entry)

        current_entry =
          entry_schema
          |> Repo.get!(entry_id)
          |> Repo.preload(Brando.Blueprint.preloads_for(entry_schema))

        # An entry in the trash is not published (the scheduled revision's
        # job is cancelled). Read under the lock, so trashing can't slip in.
        if publish? and Map.get(current_entry, :deleted_at), do: Repo.rollback(:in_trash)

        restore_params = prepare_restore_params(target_entry, current_entry, publish?)

        changeset =
          current_entry
          |> entry_schema.changeset(restore_params, user, nil, cast_blocks: true)
          |> Brando.Trait.run_trait_before_save_callbacks(entry_schema, user)

        with :ok <- Brando.Authorization.Boundary.change(user, :update, changeset),
             {:ok, updated_entry} <- Query.update(changeset),
             {:ok, identifier_result} <- Content.update_identifier(entry_schema, updated_entry),
             {:ok, _} <- Brando.Publisher.schedule_publishing(updated_entry, changeset, user) do
          replaced = active_revision_number(to_string(entry_schema), entry_id)
          deactivate_all_revisions(to_string(entry_schema), entry_id)
          activate_revision(revision)
          Brando.Activity.revision_restored(updated_entry, user, revision_number, replaced, publish?: publish?)

          %{
            changeset: changeset,
            entry: updated_entry,
            identifier_id: identifier_id(identifier_result)
          }
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, %{changeset: changeset, entry: entry, identifier_id: identifier_id}} ->
        Brando.Blueprint.AfterSave.run(entry_schema, entry, changeset, user)
        # Restoring writes past the context mutations, which queue this for
        # ordinary saves.
        Brando.Translations.source_saved(entry)
        Content.Blocks.enqueue_entry_cascade(entry_schema, entry, identifier_id)
        Content.Blocks.enqueue_entry_for_render(%{schema: to_string(entry_schema), entry_id: entry.id})
        Cache.Query.evict({:ok, entry})
        Brando.MarkdownSources.Publication.entry_saved(entry, user)
        broadcast_restored(entry_schema, entry)
        # Whoever has the entry open moves onto the restored rows, keeping
        # their unsaved work: the revisions drawer, a scheduled activation.
        Brando.EditSession.sync_saved(entry)
        {:ok, entry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Get and decode a numbered revision."
  def get_revision(entry_type, entry_id, revision_number) do
    revision_number = normalize_revision_number(revision_number)

    entry_type
    |> revision_query(entry_id)
    |> where([r], r.revision == ^revision_number)
    |> limit(1)
    |> fetch_and_decode()
  end

  defp snapshot_entry(entry_type, entry) do
    Repo.preload(entry, Brando.Blueprint.preloads_for(entry_type))
  end

  defp cancel_pending_activation!(_entry_schema, _entry_id, _revision_number, true), do: :ok

  defp cancel_pending_activation!(entry_schema, entry_id, revision_number, false) do
    case Brando.Publisher.cancel_scheduled_revision(entry_schema, entry_id, revision_number) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  The params that restore `revision_entry`, a decoded revision, onto
  `current_entry`, the entry as it is now: its fields and associations,
  without render output, and without moving the entry into or out of the
  trash (see `set_entry_to_revision/5`, which uses the same rule).
  """
  @spec restore_params(struct(), struct()) :: map()
  def restore_params(revision_entry, current_entry), do: prepare_restore_params(revision_entry, current_entry, false)

  # The entry's expiry is a plan for the entry, not content of the revision:
  # restoring one keeps the expiry the entry has now. So is the trash:
  # restoring never moves the entry into or out of it (`deleted_at`). The
  # fields the trash obfuscates (a page's `uri`) are kept as the entry has
  # them when either is in the trash: a revision taken there holds their
  # trash form, and an entry there must not take back the names it freed.
  defp prepare_restore_params(target_entry, current_entry, publish?) do
    params =
      target_entry
      |> Utils.map_from_struct()
      |> Enum.reject(fn {key, _value} -> key |> to_string() |> String.starts_with?("rendered_") end)
      |> Map.new()
      |> Map.drop([:unpublish_at, :deleted_at])
      |> drop_obfuscated_if_trashed(target_entry)
      |> drop_obfuscated_if_trashed(current_entry)

    if publish? do
      params
      |> maybe_put_existing(:status, :published)
      |> maybe_put_existing(:publish_at, DateTime.utc_now() |> DateTime.truncate(:second))
    else
      params
    end
  end

  defp drop_obfuscated_if_trashed(params, %{deleted_at: %{}} = entry), do: Map.drop(params, obfuscated_fields(entry))
  defp drop_obfuscated_if_trashed(params, _entry), do: params

  defp obfuscated_fields(%schema{}) do
    if schema.has_trait(Brando.Trait.SoftDelete),
      do: Keyword.get(schema.__trait__(Brando.Trait.SoftDelete), :obfuscated_fields, []),
      else: []
  end

  # Removing a root block deletes its entry-specific join row while the shared
  # content block remains. Recreate that link before casting the historical
  # tree so Ecto can match and update the existing nested block instead of
  # trying to insert a new belongs_to alongside the old `block_id`.
  defp restore_missing_block_links!(entry_schema, entry_id, target_entry) do
    if function_exported?(entry_schema, :__blocks_fields__, 0) do
      Enum.each(entry_schema.__blocks_fields__(), fn block_field ->
        restore_missing_block_field_links!(entry_schema, entry_id, target_entry, block_field)
      end)
    end
  end

  defp restore_missing_block_field_links!(entry_schema, entry_id, target_entry, block_field) do
    association_name = :"entry_#{block_field.name}"
    entry_block_schema = entry_schema.__schema__(:association, association_name).related
    block_schema = entry_block_schema.__schema__(:association, :block).related

    target_entry
    |> Map.get(association_name, [])
    |> Enum.each(fn entry_block ->
      restore_missing_block_link!(entry_block_schema, block_schema, entry_id, entry_block)
    end)
  end

  defp restore_missing_block_link!(_entry_block_schema, _block_schema, _entry_id, %{id: nil}), do: :ok

  defp restore_missing_block_link!(entry_block_schema, block_schema, entry_id, entry_block) do
    if is_nil(Repo.get(entry_block_schema, entry_block.id)) do
      if Repo.get(block_schema, entry_block.block_id) do
        Repo.insert_all(
          entry_block_schema,
          [
            %{
              id: entry_block.id,
              entry_id: entry_id,
              block_id: entry_block.block_id,
              sequence: entry_block.sequence
            }
          ],
          on_conflict: :nothing
        )
      else
        Repo.rollback({:revision, {:missing_block, entry_block.block_id}})
      end
    end
  end

  defp maybe_put_existing(params, key, value) do
    if Map.has_key?(params, key), do: Map.put(params, key, value), else: params
  end

  defp revision_query(entry_type, entry_id) do
    entry_type_binary = to_string(entry_type)
    entry_id = normalize_entry_id(entry_id)

    from(r in Revision, where: r.entry_type == ^entry_type_binary and r.entry_id == ^entry_id)
    |> Brando.Authorization.Boundary.subject_query(entry_type, entry_id)
  end

  defp fetch_and_decode(query) do
    case Repo.one(query) do
      nil -> :error
      revision -> decode_result(revision)
    end
  end

  defp decode_result(revision) do
    case decode_revision(revision) do
      {:ok, entry} -> {:ok, {revision, {revision.revision, entry}}}
      {:error, reason} -> {:error, {:revision, reason}}
    end
  end

  @doc """
  The blocks stored revisions hold: every block id found anywhere in a
  revision's entry, with the revisions it was found in.

  Restoring a revision re-links the blocks it holds, and fails if one is
  gone (see `set_entry_to_revision/5`), so a block in this map is still
  needed however unlinked it looks.

  A revision is read for its block ids even when a restore would refuse it
  (a snapshot naming something the code no longer has): this is a question
  of what might be needed, so it errs toward holding. The stored snapshots
  are the site's own data.

  Returns `{%{block_id => [%{entry_type:, entry_id:, revision:}]}, undecodable}`;
  `undecodable` counts revisions that could not be read at all, whose blocks
  are therefore unknown.
  """
  @spec held_block_ids() :: {%{optional(integer()) => [map()]}, non_neg_integer()}
  def held_block_ids do
    from(r in Revision, select: map(r, [:entry_type, :entry_id, :revision, :encoded_entry]))
    |> Repo.all()
    |> Enum.reduce({%{}, 0}, fn revision, {held, undecodable} ->
      case decode_for_audit(revision.encoded_entry) do
        {:ok, entry} ->
          {hold_block_ids(held, entry, revision), undecodable}

        {:error, _} ->
          {held, undecodable + 1}
      end
    end)
  end

  defp hold_block_ids(held, entry, revision) do
    holder = Map.take(revision, [:entry_type, :entry_id, :revision])

    entry
    |> collect_block_ids(MapSet.new())
    |> Enum.reduce(held, fn id, acc -> Map.update(acc, id, [holder], &[holder | &1]) end)
  end

  defp decode_for_audit(encoded_entry) do
    {:ok, :erlang.binary_to_term(encoded_entry)}
  rescue
    _ -> {:error, :invalid_snapshot}
  end

  # Every block id in a decoded entry, however deep: a block struct's own id,
  # and any `block_id` a join row or an owned record carries.
  defp collect_block_ids(%Ecto.Association.NotLoaded{}, acc), do: acc

  defp collect_block_ids(%{__struct__: Brando.Content.Block, id: id} = block, acc) do
    acc = if is_integer(id), do: MapSet.put(acc, id), else: acc
    block |> Map.from_struct() |> Map.values() |> collect_block_ids(acc)
  end

  defp collect_block_ids(%{__struct__: _} = struct, acc) do
    acc =
      case struct do
        %{block_id: id} when is_integer(id) -> MapSet.put(acc, id)
        _ -> acc
      end

    struct |> Map.from_struct() |> Map.values() |> collect_block_ids(acc)
  end

  defp collect_block_ids(map, acc) when is_map(map), do: map |> Map.values() |> collect_block_ids(acc)
  defp collect_block_ids(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_block_ids/2)
  defp collect_block_ids(tuple, acc) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> collect_block_ids(acc)
  defp collect_block_ids(_other, acc), do: acc

  defp safe_decode(encoded_entry) do
    {:ok, :erlang.binary_to_term(encoded_entry, [:safe])}
  rescue
    _ -> {:error, :invalid_snapshot}
  end

  defp decode_revision(revision) do
    with {:ok, entry} <- safe_decode(revision.encoded_entry),
         true <- valid_revision_entry?(entry, revision) do
      {:ok, entry}
    else
      _ -> {:error, :invalid_snapshot}
    end
  end

  defp valid_revision_entry?(%{__struct__: entry_schema, id: entry_id}, revision) do
    to_string(entry_schema) == revision.entry_type and entry_id == revision.entry_id
  end

  defp valid_revision_entry?(_entry, _revision), do: false

  defp decode_revision!(revision) do
    case decode_revision(revision) do
      {:ok, entry} -> entry
      {:error, reason} -> Repo.rollback({:revision, reason})
    end
  end

  defp get_revision_record!(entry_type, entry_id, revision_number) do
    query =
      entry_type
      |> revision_query(entry_id)
      |> where([r], r.revision == ^revision_number)

    Repo.one(query) || Repo.rollback({:revision, :not_found})
  end

  defp lock_entry!(entry_type, entry_id) do
    query = from(entry in entry_type, where: entry.id == ^entry_id, select: entry.id, lock: "FOR UPDATE")

    case Repo.one(query) do
      nil -> Repo.rollback({:entry, :not_found})
      _id -> :ok
    end
  end

  defp next_revision(entry_type, entry_id) do
    from(r in Revision,
      select: max(r.revision),
      where: r.entry_type == ^entry_type and r.entry_id == ^entry_id
    )
    |> Repo.one()
    |> case do
      nil -> 0
      revision -> revision + 1
    end
  end

  defp activate_revision(revision) do
    from(r in Revision,
      where:
        r.entry_type == ^revision.entry_type and r.entry_id == ^revision.entry_id and
          r.revision == ^revision.revision,
      update: [set: [active: true, scheduled: false]]
    )
    |> Repo.update_all([])
  end

  defp active_revision_number(entry_type, entry_id) do
    from(r in Revision,
      where: r.active == true and r.entry_type == ^entry_type and r.entry_id == ^entry_id,
      select: r.revision,
      limit: 1
    )
    |> Repo.one()
  end

  defp deactivate_all_revisions(entry_type, entry_id) do
    from(r in Revision,
      where: r.active == true and r.entry_type == ^entry_type and r.entry_id == ^entry_id,
      update: [set: [active: false]]
    )
    |> Repo.update_all([])
  end

  defp identifier_id(%Brando.Content.Identifier{id: id}), do: id
  defp identifier_id(_), do: nil

  defp user_id(:system), do: nil
  defp user_id(%{id: id}), do: id

  defp normalize_entry_id(entry_id) when is_integer(entry_id), do: entry_id
  defp normalize_entry_id(entry_id) when is_binary(entry_id), do: String.to_integer(entry_id)

  defp normalize_revision_number(revision_number) when is_integer(revision_number), do: revision_number
  defp normalize_revision_number(revision_number) when is_binary(revision_number), do: String.to_integer(revision_number)

  defp broadcast_restored(schema, entry) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.scoped("brando:mutations:#{inspect(schema)}"),
      {:mutation, schema, entry, :updated}
    )
  end
end
