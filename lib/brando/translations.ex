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

  use Brando.Tracing.Decorator

  import Ecto.Query

  require Logger

  alias Brando.Blueprint.Unique
  alias Brando.Content.Blocks
  alias Brando.Content.Identifier
  alias Brando.Repo
  alias Brando.Translations.Group
  alias Brando.Translations.Member
  alias Brando.Translations.PendingVersion
  alias Brando.Translations.SharedGalleries
  alias Brando.Translations.Sync
  alias Brando.Translations.WorkItem
  alias Brando.Utils
  alias Ecto.Changeset

  # A work item as it is carried, resolved and opened again
  @item_fields [:path, :kind, :source_digest, :source_previous, :minor]

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
                       counts: %{translate: 2, review: 1}, in_trash: false}, ...]}

  Only a member's current pending version counts; superseded ones are
  ignored, and a pending version with no open item still reads as pending
  — a structural or shared update without text work. A version in the trash
  is listed with `in_trash: true`: it still holds its language, but is not a
  version to show. With an `actor`, only versions the actor may read are
  listed.
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
      trashed = MapSet.new(trashed_ids(schema, Enum.map(members, & &1.entry_id)))

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
               counts: Map.get(counts, version_id, %{}),
               in_trash: MapSet.member?(trashed, member.entry_id)
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
  translation is created for their languages. A deleted entry keeps its
  alternate link but no longer holds its language.
  """
  def alternate_languages(schema, entry_id) do
    if schema.has_alternates?() do
      from(a in Module.concat(schema, Alternate),
        join: e in ^schema,
        on: e.id == a.linked_entry_id,
        where: a.entry_id == ^entry_id,
        select: e.language
      )
      |> exclude_deleted(schema)
      |> Repo.all()
      |> Enum.map(&to_string/1)
    else
      []
    end
  end

  @doc """
  The other language versions of `entry` that `actor` may read, for its form:
  `linked`, the entries linked to it as alternates, those in the trash
  included, and `unlinked`, those not in the trash that hold its `matched_by`
  values (`trait :translatable, matched_by: [...]`) in another language
  without being linked to it. `unlinked` is empty for a schema without
  `matched_by`, or for an entry with a nil `matched_by` value.
  """
  def language_versions(schema, %{id: id} = entry, actor) do
    linked_ids = if schema.has_alternates?(), do: alternate_ids(schema, id), else: []

    linked =
      from(e in schema, where: e.id in ^linked_ids, order_by: [asc: e.language, asc: e.id])
      |> readable(schema, actor)
      |> Repo.all()

    unlinked =
      case same_values_query(schema, entry) do
        nil ->
          []

        query ->
          from(e in query, where: e.id not in ^linked_ids, order_by: [asc: e.language, asc: e.id])
          |> readable(schema, actor)
          |> Repo.all()
      end

    %{linked: linked, unlinked: unlinked}
  end

  @doc "The entries of `schema` in other languages than `entry`'s, not in the trash, that `actor` may read."
  def other_language_entries(schema, entry, actor) do
    from(e in schema, where: e.language != ^entry.language, order_by: [asc: e.language, asc: e.id])
    |> exclude_trashed(schema)
    |> readable(schema, actor)
    |> Repo.all()
  end

  defp alternate_ids(schema, id),
    do: Repo.all(from a in Module.concat(schema, Alternate), where: a.entry_id == ^id, select: a.linked_entry_id)

  # The entries of `schema` in other languages, not in the trash, with
  # `entry`'s `matched_by` values; nil without `matched_by`, or when one of
  # `entry`'s values is nil: no other entry shares a value it lacks
  defp same_values_query(schema, entry) do
    values = Enum.map(matched_by(schema), &{&1, Map.get(entry, &1)})

    if values != [] and Enum.all?(values, fn {_field, value} -> not is_nil(value) end) do
      query = from(e in schema, where: e.id != ^entry.id and e.language != ^entry.language)

      values
      |> Enum.reduce(query, fn {field, value}, query -> from(e in query, where: field(e, ^field) == ^value) end)
      |> exclude_trashed(schema)
    end
  end

  @doc "The attributes `schema` matches its language versions by (`trait :translatable, matched_by: [...]`)."
  def matched_by(schema) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__translatable_matched_by__, 0),
      do: schema.__translatable_matched_by__(),
      else: []
  end

  defp exclude_trashed(query, schema) do
    if :deleted_at in schema.__schema__(:fields), do: where(query, [e], is_nil(e.deleted_at)), else: query
  end

  defp readable(query, _schema, nil), do: query
  defp readable(query, schema, actor), do: Brando.Content.Transfer.Catalog.scoped_query(query, schema, actor, :read)

  @doc """
  The site's languages (`Brando.Languages`) of `schema` that `entry` has no
  version in yet: neither a member of its group nor an alternate linked to
  its source (an existing, independent version is not joined to a group).
  For an entry outside a group, its own language and its alternates'.
  """
  def missing_languages(schema, %{id: id} = entry) do
    taken =
      case synchronized?(schema) && get_member(schema, id) do
        %Member{group_id: group_id} ->
          members = list_members(group_id)
          source = Enum.find(members, &(&1.role == :source))
          alternates = if source, do: alternate_languages(schema, source.entry_id), else: []
          Enum.map(members, & &1.language) ++ alternates

        _ ->
          [to_string(entry.language) | alternate_languages(schema, id)]
      end

    taken = taken ++ unlinked_languages(schema, entry)

    site = Brando.Languages.codes()

    for value <- Ecto.Enum.values(schema, :language),
        code = to_string(value),
        code in site,
        code not in taken,
        do: code
  end

  # The languages of the entries with `entry`'s `matched_by` values
  defp unlinked_languages(schema, entry) do
    case same_values_query(schema, entry) do
      nil -> []
      query -> query |> select([e], e.language) |> Repo.all() |> Enum.map(&to_string/1)
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

  Every text the copy holds that is not empty is marked `:translate`, as if
  it were new: until it is translated or marked reviewed, the copy is still
  the source's text. Pass `mark_translate: false` for a translation meant to
  start from the source's text as it is, such as a language variant that
  differs in a few places; nothing is marked then.

  Returns `{:error, :language_exists}` when the group already has that
  language, or when the source is linked to an independent version in it.
  """
  def create_target(schema, source_id, language, actor, opts \\ []) do
    language = to_string(language)
    mark_translate? = Keyword.get(opts, :mark_translate, true)

    with :ok <- ensure_duplicable(schema),
         :ok <- ensure_language_known(schema, language),
         :ok <- ensure_no_linked_version(schema, source_id, language),
         :ok <- ensure_no_unlinked_version(schema, source_id, language) do
      # One transaction, enrolment included: a failed copy leaves no group
      # with a source and no translation behind.
      Repo.transaction(fn -> enrol_target(schema, source_id, language, actor, mark_translate?) end)
    end
  end

  @doc """
  Creates the `language` translation of a synchronized source as
  `create_target/5` does, after deleting for good the group's version in that
  language if it is in the trash. Only the admin calls it, once the editor has
  confirmed; proposals and `create_target/5` refuse a language in the trash.

  In one transaction: the version in the trash is deleted the way the trash's
  purge deletes it (`Brando.SoftDelete.Query.purge_entries/3`: its group
  member with its pending versions and work items, its alternate link, the
  context's `before_purge/2`), then the translation is created. If the create
  fails, the version is still in the trash as it was.

  Deleting it takes permission to delete it: `actor` without it is refused
  with `{:error, :language_in_trash}`, as `create_target/5` refuses. A
  language with no version is created as `create_target/5` creates it; one
  whose version is not in the trash is refused with `{:error, :language_exists}`.
  """
  def replace_trashed_target(schema, source_id, language, actor, opts \\ []) do
    language = to_string(language)
    mark_translate? = Keyword.get(opts, :mark_translate, true)

    with :ok <- ensure_duplicable(schema),
         :ok <- ensure_language_known(schema, language),
         :ok <- ensure_no_linked_version(schema, source_id, language),
         :ok <- ensure_no_unlinked_version(schema, source_id, language) do
      Repo.transaction(fn -> replace_target(schema, source_id, language, actor, mark_translate?) end)
    end
  end

  defp replace_target(schema, source_id, language, actor, mark_translate?) do
    with {:ok, source_member} <- source_member(schema, source_id, actor),
         :ok <- purge_trashed_version(schema, source_member, language, actor),
         {:ok, target} <- insert_target(schema, source_member, source_id, language, actor, mark_translate?) do
      target
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp purge_trashed_version(schema, %Member{group_id: group_id}, language, actor) do
    case Repo.one(from m in Member, where: m.group_id == ^group_id and m.language == ^language, select: m.entry_id) do
      nil ->
        :ok

      entry_id ->
        # Locked, so a restore waits for the delete
        trashed =
          if :deleted_at in schema.__schema__(:fields),
            do: Repo.one(from e in schema, where: e.id == ^entry_id and not is_nil(e.deleted_at), lock: "FOR UPDATE")

        cond do
          is_nil(trashed) -> {:error, :language_exists}
          not may_delete_for_good?(actor, trashed) -> {:error, :language_in_trash}
          true -> Brando.SoftDelete.Query.purge_entries(schema, [entry_id], actor, %{"replaced" => true})
        end
    end
  end

  # What deleting an entry takes: the delete permission, and for a published
  # one the publish permission too, as trashing it does. A version trashed
  # while published still has that status.
  defp may_delete_for_good?(actor, entry) do
    alias Brando.Authorization.Boundary

    Boundary.authorize(actor, :delete, entry) == :ok and
      (Map.get(entry, :status) != :published or Boundary.authorize(actor, :publish, entry) == :ok)
  end

  defp enrol_target(schema, source_id, language, actor, mark_translate?) do
    with {:ok, source_member} <- source_member(schema, source_id, actor),
         :ok <- ensure_language_free(schema, source_member, language),
         {:ok, target} <- insert_target(schema, source_member, source_id, language, actor, mark_translate?) do
      target
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  Whether translations of `schema` can be created: its context must be able to
  duplicate an entry (`mutation :duplicate` in the context), since a
  translation starts as a copy of its source.
  """
  def duplicable?(schema) do
    context = schema.__modules__().context

    Code.ensure_loaded?(context) and
      function_exported?(context, :"duplicate_#{schema.__naming__().singular}", 3)
  end

  defp ensure_duplicable(schema), do: if(duplicable?(schema), do: :ok, else: {:error, :not_duplicable})

  defp insert_target(schema, source_member, source_id, language, actor, mark_translate?) do
    with {:ok, target} <- duplicate_to_language(schema, source_id, language, actor),
         {:ok, source} <- load_entry(schema, source_id) do
      if schema.has_alternates?(), do: Module.concat(schema, Alternate).add(source_id, target.id)
      group = Repo.get!(Group, source_member.group_id)
      uids = module_uids([source], schema)

      member =
        Repo.insert!(%Member{
          group_id: group.id,
          entry_type: entry_type(schema),
          entry_id: target.id,
          language: language,
          role: :target,
          synchronized: true,
          last_synced_generation: group.source_generation,
          baseline: Sync.baseline_for(source, schema, nil, uids),
          baseline_texts: Sync.baseline_texts_for(source, schema, nil, uids)
        })

      # The copy still links to the source language's content; its first
      # pending version points those links at this language's versions, and
      # marks the text it copied to translate.
      sync_member(schema, source, member, group.source_generation, false, translate_all: mark_translate?)

      {:ok, target}
    end
  end

  @doc """
  Stops synchronizing one target.

  Its content, pending edits and alternate link stay; structure and shared
  fields become editable. Pending versions are marked superseded. The source
  cannot be made independent — transfer the role first.

  A synchronized target shows the source's gallery records (gallery variables
  and assets point at them). Each one the target shares with another version
  of its group is copied for it (`split_shared_galleries/3`), so its galleries
  are its own from then on.
  """
  def make_independent(schema, entry_id, actor) do
    case get_member(schema, entry_id) do
      nil ->
        {:error, :not_enrolled}

      %Member{role: :source} ->
        {:error, :is_source}

      %Member{synchronized: false} = member ->
        {:ok, member}

      member ->
        Repo.transaction(fn -> detach(schema, member, actor) end)
    end
  end

  defp detach(schema, member, actor) do
    supersede_pending(member.id)
    split_or_rollback(schema, member, actor)

    member
    |> Changeset.change(synchronized: false, detached_at: now())
    |> Repo.update!()
  end

  defp split_or_rollback(schema, member, actor) do
    case split_member_galleries(schema, member, actor) do
      {:ok, copies} -> copies
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  The rows of an entry that point at a gallery record another version of its
  group points at too, as `Brando.Translations.SharedGalleries` holders. `[]`
  for an entry outside a group.

  While a translation follows the source that is expected. An independent one
  that shares a gallery changes the other version when its gallery is edited:
  `split_shared_galleries/3` repairs it.
  """
  def shared_galleries(schema, entry_id) do
    with %Member{} = member <- get_member(schema, entry_id),
         {:ok, entry, others} <- load_group_entries(schema, member) do
      SharedGalleries.shared(entry, others)
    else
      _ -> []
    end
  end

  @doc """
  Gives an entry its own copy of every gallery record it shares with another
  version of its group (`shared_galleries/2`). `make_independent/3` does this;
  call it to repair a translation made independent before it did.

  Returns `{:ok, copies}`, each holder (`Brando.Translations.SharedGalleries`)
  with its new gallery, or `{:error, :not_enrolled}`.
  """
  def split_shared_galleries(schema, entry_id, actor) do
    case get_member(schema, entry_id) do
      %Member{} = member -> Repo.transaction(fn -> split_or_rollback(schema, member, actor) end)
      nil -> {:error, :not_enrolled}
    end
  end

  @doc """
  `split_shared_galleries/3` for a member of a group, as `:system`: after an
  independent translation is saved (`Brando.Worker.TranslationSync`), so a
  save that wrote another version's gallery back (a form opened before Make
  independent, a restored revision) gets its own copy again.
  """
  def split_member_shared_galleries(member_id) do
    with %Member{role: :target, synchronized: false} = member <- Repo.get(Member, member_id),
         schema when not is_nil(schema) <- Brando.Blueprint.from_name(member.entry_type) do
      Repo.transaction(fn -> split_or_rollback(schema, member, :system) end)
    else
      _ -> {:ok, []}
    end
  end

  defp split_member_galleries(schema, member, actor) do
    case load_group_entries(schema, member) do
      {:ok, entry, others} -> SharedGalleries.split(entry, others, actor)
      {:error, _} -> {:ok, []}
    end
  end

  # The member's entry and the entries of the other members of its group.
  # Deleted versions count too: restored, they would share again.
  defp load_group_entries(schema, member) do
    with {:ok, entry} <- load_entry(schema, member.entry_id, with_deleted: true) do
      others =
        for %Member{entry_id: id} <- list_members(member.group_id),
            id != member.entry_id,
            {:ok, other} <- [load_entry(schema, id, with_deleted: true)],
            do: other

      {:ok, entry, others}
    end
  end

  @doc """
  Makes a synchronized target the source of its group.

  The former source becomes a synchronized target. Every member's baseline is
  reset to the new source, so the switch itself raises no review work; the next
  source save synchronizes structure from the new source. Reviews still open
  stay open, read against the new source, without the former source's text
  before the change (`source_previous`).
  """
  def transfer_source(schema, new_source_id, _actor) do
    with %Member{role: :target, synchronized: true} = new_source <- get_member(schema, new_source_id),
         {:ok, entry} <- load_entry(schema, new_source_id) do
      uids = module_uids([entry], schema)
      baseline = Sync.baseline_for(entry, schema, nil, uids)
      baseline_texts = Sync.baseline_texts_for(entry, schema, nil, uids)

      Repo.transaction(fn ->
        lock_for_transfer!(new_source)

        from(m in Member, where: m.group_id == ^new_source.group_id and m.role == :source)
        |> Repo.update_all(set: [role: :target, synchronized: true, updated_at: naive_now()])

        from(m in Member, where: m.group_id == ^new_source.group_id and m.id != ^new_source.id)
        |> Repo.update_all(set: [baseline: baseline, baseline_texts: baseline_texts, updated_at: naive_now()])

        supersede_pending(new_source.id)
        forget_previous_texts(new_source.group_id)

        # A source keeps no baseline. The member was loaded without its texts,
        # so they are written whatever the struct holds
        new_source
        |> Changeset.change(role: :source)
        |> Changeset.force_change(:baseline, %{})
        |> Changeset.force_change(:baseline_texts, %{})
        |> Repo.update!()
      end)
    else
      nil -> {:error, :not_enrolled}
      %Member{} -> {:error, :not_a_synchronized_target}
      error -> error
    end
  end

  # Under the group's lock, as a synchronization takes it: one that had listed
  # the members before the transfer committed would write the former source's
  # digests over the baselines the transfer sets. The member is read again
  # under it, as it may have been made independent meanwhile.
  defp lock_for_transfer!(%Member{id: id, group_id: group_id}) do
    Repo.one!(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE")

    case Repo.get(Member, id) do
      %Member{role: :target, synchronized: true} -> :ok
      _ -> Repo.rollback(:not_a_synchronized_target)
    end
  end

  @doc """
  Called after an entry is saved. When it is the source of a group with
  synchronized targets, enqueues their synchronization.

  `minor: true` marks a save of minor text corrections: changed source text
  raises no review work. `resync: false` skips the recompute of a saved
  synchronized translation, for a caller that runs `target_saved/3` itself, as
  the admin form does.
  """
  def source_saved(%schema{id: id}, opts \\ []) do
    with true <- synchronized?(schema),
         %Member{} = member <- get_member(schema, id) do
      member_saved(member, opts)
    else
      _ -> :ok
    end
  end

  defp member_saved(%Member{role: :source, group_id: group_id}, opts),
    do: enqueue_sync(group_id, Keyword.get(opts, :minor, false))

  # A saved translation gets its pending version recomputed against what was
  # saved, so applying it later keeps the new text.
  defp member_saved(%Member{role: :target, synchronized: true} = member, opts) do
    if Keyword.get(opts, :resync, true), do: enqueue_resync(member), else: :ok
  end

  # An independent translation's save may write a gallery another version
  # uses (a form opened before Make independent, a restored revision): it
  # gets its own copy again.
  # One waiting split per translation: saves in a row queue one. Without
  # tenancy the nil prefix gives the key a value to compare.
  defp member_saved(%Member{role: :target, synchronized: false, id: member_id}, _opts) do
    %{"split_galleries" => member_id}
    |> Brando.Tenant.Job.attach()
    |> Map.put_new("tenant_prefix", nil)
    |> Brando.Worker.TranslationSync.new(
      unique: [period: :infinity, keys: [:split_galleries, :tenant_prefix], states: [:available, :scheduled]]
    )
    |> Oban.insert()
  end

  defp member_saved(_member, _opts), do: :ok

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
  over; nothing new is asked for review. `{:error, :group_not_found}` when the
  group is gone, its source deleted since.
  """
  def resync_target(group_id, member_id) do
    Repo.transaction(fn ->
      group =
        Repo.one(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE") ||
          Repo.rollback(:group_not_found)

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
      pending = if member.role == :target and member.synchronized, do: fresh_pending(schema, member)

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
      pending text, or the path was acknowledged, unless the save left the
      structure, media or shared values of the block, ref, var or row it is
      in as they were (a form without that field)
    * `:shared_update` and `:relinked` — when the saved value is the pending one
    * `:awaiting_translation` — never; it resolves when the link can be made

  The pending version is then recomputed against the saved content, carrying
  unresolved work. Returns `{:ok, %{open: count, stale: boolean}}`; `stale`
  means the source was saved again after the loaded version was computed.
  """
  @decorate span("brando.translations.target_saved", schema: :schema, entry_id: :entry_id)
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
      {:ok, source} ->
        sync_member(schema, source, member, group.source_generation, false, previous: previous, with_deleted: true)

      :error ->
        :ok
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
  the saved translation when none was loaded. A field may also keep its
  saved content whole: a form without a block field, or without an input for
  a shared value, can't hold the pending version's, and what the save leaves
  stays pending. Any other difference refuses the save with the paths that
  differ: `{:error, {:source_controlled, paths}}`.

  New blocks and table rows keep the sync identity the pending version gave
  them, which the form does not carry.

  Entries outside a group, sources and independent translations pass through.
  """
  @decorate span("brando.translations.check_target_save", schema: :schema, entry_id: :entry_id)
  def check_target_save(schema, entry_id, %Changeset{} = changeset, version_id \\ nil) do
    with true <- synchronized?(schema),
         %Member{role: :target, synchronized: true} = member <- get_member(schema, entry_id) do
      # A translation in the trash opens and saves in the form like any other
      {:ok, saved} = load_entry(schema, entry_id, with_deleted: true)

      reference =
        case reviewed_version(member, %{version_id: version_id}) do
          nil -> saved
          version -> pending_content(version, saved)
        end

      changeset = restore_sync_identities(changeset, schema, reference)
      submitted = Changeset.apply_changes(changeset)
      module_uids = module_uids([reference, saved, submitted], schema)
      [expected, kept, actual] = Enum.map([reference, saved, submitted], &owned_by_field(&1, schema, module_uids))

      differing =
        for field <- Enum.uniq(Map.keys(expected) ++ Map.keys(actual)),
            [rows, wanted] = [Map.get(actual, field, []), Map.get(expected, field, [])],
            rows not in [wanted, Map.get(kept, field, [])],
            row <- (wanted -- rows) ++ (rows -- wanted),
            do: row

      case differing do
        [] -> {:ok, changeset}
        rows -> {:error, {:source_controlled, paths(rows)}}
      end
    else
      _ -> {:ok, changeset}
    end
  end

  @doc """
  Whether `payload`, a pending version's content (`pending_content/2`),
  differs from `saved`, the translation it was computed for, in what
  follows the source: structure, media, links or source-controlled values.
  Saving the pending version saves those with its text.
  """
  def structure_changed?(schema, saved, payload) do
    uids = module_uids([saved, payload], schema)
    owned_by_field(saved, schema, uids) != owned_by_field(payload, schema, uids)
  end

  # Owned rows by the entry field their path starts with: a field is kept or
  # taken whole, never a mix of the saved and the pending version's rows.
  defp owned_by_field(entry, schema, module_uids) do
    entry
    |> Sync.owned_rows(schema, nil, module_uids)
    |> Enum.group_by(fn {path, _class, _value} -> path_field(path) end)
    |> Map.new(fn {field, rows} -> {field, Enum.sort(rows)} end)
  end

  defp path_field(path), do: path |> String.split("/", parts: 2) |> hd()

  defp paths(rows), do: rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

  # A block the pending version added is new to the form, which gives it a
  # fresh `sync_uid`; put back the one the source assigned, found by `uid`.
  defp restore_sync_identities(changeset, schema, reference) do
    blocks = reference_blocks(reference, schema)

    Enum.reduce(blocks_fields(schema), changeset, fn field, changeset ->
      case Changeset.get_change(changeset, field) do
        joins when is_list(joins) ->
          Changeset.put_change(changeset, field, joins |> kept_rows() |> Enum.map(&restore_join(&1, blocks)))

        _ ->
          changeset
      end
    end)
  end

  # A row the changeset replaces (one `Brando.Drafts.Restore` left out) is
  # left out again: `put_change/3` raises on a `:replace` changeset, and
  # replaces the row again by itself.
  defp kept_rows(rows), do: Enum.reject(rows, &match?(%Changeset{action: :replace}, &1))

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
          |> kept_rows()
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
        Changeset.put_change(block, :children, children |> kept_rows() |> Enum.map(&restore_child(&1, blocks)))

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
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__blocks_fields__, 0),
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
    {:ok, saved} = load_entry(schema, member.entry_id, with_deleted: true)
    payload = pending_content(reviewed, saved)
    module_uids = module_uids([saved, payload], schema)
    saved_rows = rows_by_path(saved, schema, module_uids)
    reviewed_rows = rows_by_path(payload, schema, module_uids)
    reviewed_work = MapSet.new(reviewed.work_items, &{&1.path, &1.source_digest})

    reviewed_translate =
      for %{kind: :translate} = item <- reviewed.work_items, into: %{}, do: {item.path, item.source_digest}

    reviewed_paths = MapSet.new(reviewed.work_items, & &1.path)

    acknowledged = MapSet.new(List.wrap(review[:acknowledged]))
    left = unapplied(saved, payload, schema, module_uids)
    timestamp = now()

    items =
      Enum.map(current.work_items, fn item ->
        completed? =
          is_nil(item.resolved_at) and not within?(item.path, left) and
            done?(item, saved_rows, reviewed_rows, acknowledged)

        cond do
          completed? and MapSet.member?(reviewed_work, {item.path, item.source_digest}) ->
            item
            |> Changeset.change(resolved_at: timestamp, resolved_generation: reviewed.source_generation)
            |> Repo.update!()

          # Translated from an older source text: the source changed it while
          # the editor worked, so the translation is to review now.
          completed? and item.kind == :translate and Map.has_key?(reviewed_translate, item.path) ->
            item |> Changeset.change(kind: :review) |> Repo.update!()

          # Answered from the source's text the loaded version was computed
          # against, which Brando does not keep: the source's text before the
          # change is no longer what the translation was written from
          completed? and item.kind == :review and is_binary(item.source_previous) and
              MapSet.member?(reviewed_paths, item.path) ->
            item |> Changeset.change(source_previous: nil) |> Repo.update!()

          true ->
            item
        end
      end)

    current
    |> Changeset.change(status: :applied, applied_at: timestamp)
    |> Repo.update!()
    |> Map.put(:work_items, items)
  end

  # The blocks, refs, vars and rows whose structure or shared values the save
  # left as they were, not the reviewed version's: a form without their field
  # can't hold it (`check_target_save/4`). Their saved text is no
  # translation of the pending text, so the text work within them stays
  # open. A shared value left covers what holds it: a ref's or var's media
  # its text, a row's shared field the row, a block's identifiers their
  # metas. A field's own row (its block order) is left out: a block added
  # elsewhere does not touch the others' text.
  defp unapplied(saved, payload, schema, module_uids) do
    [saved, payload] =
      Enum.map([saved, payload], fn entry ->
        for {path, class, value} <- Sync.owned_rows(entry, schema, nil, module_uids),
            String.contains?(path, "/"),
            reduce: %{},
            do: (rows -> Map.update(rows, {path, class}, [value], &[value | &1]))
      end)

    for {path, class} = key <- Enum.uniq(Map.keys(saved) ++ Map.keys(payload)),
        Enum.sort(Map.get(saved, key, [])) != Enum.sort(Map.get(payload, key, [])),
        part <- [path | holder(path, class)],
        into: MapSet.new(),
        do: part
  end

  # What a shared value belongs to: its ref, var or row, or for a block's
  # identifiers the metas kept for them.
  defp holder(path, :shared) do
    case path |> String.split("/") |> Enum.split(-1) do
      {parent, ["identifiers"]} -> [Enum.join(parent ++ ["identifier_metas"], "/")]
      {parent, _leaf} -> [Enum.join(parent, "/")]
    end
  end

  defp holder(_path, _class), do: []

  # Whether `path` is one of `parts` or lies within one
  defp within?(path, parts) do
    path
    |> String.split("/")
    |> Enum.scan(&"#{&2}/#{&1}")
    |> Enum.any?(&MapSet.member?(parts, &1))
  end

  defp done?(%WorkItem{kind: kind, path: path}, saved, reviewed, acknowledged) when kind in [:translate, :review] do
    MapSet.member?(acknowledged, path) or
      (Map.has_key?(saved, path) and not blank?(saved[path]) and saved[path] != reviewed[path])
  end

  defp done?(%WorkItem{kind: kind, path: path, source_digest: digest}, saved, _reviewed, _acknowledged)
       when kind in [:shared_update, :relinked],
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
  order, and bumps the group's `source_generation`. Returns
  `{:error, :group_not_found}` for a group deleted since the save, as undoing
  a proposal that created its first translation deletes it.
  """
  def sync_group(group_id, opts \\ []) do
    minor? = Keyword.get(opts, :minor, false)

    Repo.transaction(fn ->
      group =
        Repo.one(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE") ||
          Repo.rollback(:group_not_found)

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

  # `previous`: the version the new one supersedes (the current one by
  # default). `with_deleted`: also a translation in the trash, which only its
  # own save recomputes. `translate_all`: mark every text to translate, for a
  # new translation (`create_target/5`).
  defp sync_member(schema, source, member, generation, minor?, opts \\ []) do
    previous = Keyword.get(opts, :previous, :current)

    case load_entry(schema, member.entry_id, Keyword.take(opts, [:with_deleted])) do
      {:ok, target} ->
        member = with_baseline_texts(member)
        previous = if previous == :current, do: current_pending(member.id), else: previous
        uids = module_uids([source, target], schema)

        result =
          Sync.compute_pending(source, target, member.baseline,
            schema: schema,
            baseline_texts: member.baseline_texts,
            module_uids: uids,
            minor: minor?,
            translate_all: Keyword.get(opts, :translate_all, false),
            untranslated: untranslated(member, schema, target, previous, uids),
            identifiers: identifier_map(source, schema, member.language),
            entries: entry_map(source, schema, member.language),
            fragments: fragment_map(source, schema, member.language)
          )

        record_pending(member, result, previous, generation, schema)

        member
        |> Changeset.change(
          baseline: result.baseline,
          baseline_texts: result.baseline_texts,
          last_synced_generation: generation
        )
        |> Repo.update!()

        {member.id, :ok}

      _ ->
        {member.id, :target_not_found}
    end
  end

  # The member with the texts it keeps beside its baseline, which a member is
  # loaded without: what the sync reads, and compares its new texts with
  #
  # The baseline is read again with them: a member loaded before the group's
  # lock was taken may hold the digests of the sync before the one whose
  # texts are read here, and a review raised from that pair would take the
  # source's current text as its previous one.
  defp with_baseline_texts(%Member{id: id} = member) do
    case Repo.one(from m in Member, where: m.id == ^id, select: {m.baseline, m.baseline_texts}) do
      {baseline, texts} -> %{member | baseline: baseline || %{}, baseline_texts: texts || %{}}
      nil -> member
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

  @doc """
  Maps each of `source`'s tree relations (`Brando.Translations.Sync.tree_relations/2`,
  such as a page's parent or a fragment's page) and the id it points at,
  `{name, id}`, onto the same entry's version in `language`, or nil when
  there is no such version yet.
  """
  def entry_map(source, schema, language) do
    for {name, module} <- Sync.tree_targets(schema), id = Map.get(source, :"#{name}_id"), not is_nil(id), into: %{} do
      {{name, id}, tree_version_id(schema, module, id, language)}
    end
  end

  # A page's parent is mapped onto its linked version. An entry of another
  # schema (a fragment's page) that is in `language` already is its own version.
  defp tree_version_id(schema, schema, id, language), do: alternate_entry_id(schema, id, language)
  defp tree_version_id(_schema, module, id, language), do: version_in_language(module, id, language)

  defp version_in_language(module, id, language) do
    if exists?(from e in module, where: e.id == ^id and e.language == ^language),
      do: id,
      else: alternate_entry_id(module, id, language)
  end

  @doc """
  Maps the fragments `source`'s blocks embed onto their versions in
  `language`, leaving out those with none.
  """
  def fragment_map(source, schema, language) do
    for id <- Sync.fragment_ids(source, schema),
        version = version_in_language(Brando.Pages.Fragment, id, language),
        into: %{},
        do: {id, version}
  end

  # An `:entries` relation's join rows, pointed at the same entries' versions
  # in `language`. The copy inserts them as rows of its own. A row whose entry
  # has no version there is left out and counted on `dropped`, unless its
  # identifier is in `kept` (an entry copied in the same batch, linked once its
  # copy exists).
  defp related_in_language(rows, language, kept \\ MapSet.new(), dropped \\ nil)

  defp related_in_language([], _language, _kept, _dropped), do: []

  defp related_in_language(rows, language, kept, dropped) when is_list(rows) do
    ids = Enum.map(rows, & &1.identifier_id)
    identifiers = from(i in Identifier, where: i.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})

    rows
    |> Enum.flat_map(fn row ->
      identifier = identifiers[row.identifier_id]
      relate_row(row, identifier && counterpart_id(identifier, language), kept, dropped)
    end)
    |> Enum.uniq_by(& &1.identifier_id)
  end

  defp related_in_language(rows, _language, _kept, _dropped), do: rows

  defp relate_row(row, nil, kept, dropped) do
    cond do
      MapSet.member?(kept, row.identifier_id) -> [%{row | identifier: nil}]
      dropped -> count_dropped(dropped)
      true -> []
    end
  end

  defp relate_row(row, identifier_id, _kept, _dropped), do: [%{row | identifier_id: identifier_id, identifier: nil}]

  defp count_dropped(dropped) do
    :counters.add(dropped, 1, 1)
    []
  end

  defp counterpart_id(%Identifier{} = identifier, language) do
    case identifier_language(identifier) do
      nil -> identifier.id
      ^language -> identifier.id
      _other -> alternate_identifier_id(identifier, language)
    end
  end

  # An identifier made before its schema became translatable has no language,
  # though its entry now has one: ask the entry, or every link to it would be
  # taken as language-neutral and never mapped.
  defp identifier_language(%Identifier{language: language}) when language not in [nil, ""], do: to_string(language)

  defp identifier_language(%Identifier{schema: module, entry_id: entry_id}) do
    with true <- Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1),
         true <- :language in module.__schema__(:fields),
         language when not is_nil(language) <-
           Repo.one(from e in module, where: e.id == ^entry_id, select: e.language) do
      to_string(language)
    else
      _ -> nil
    end
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

    resync_waiting_tree(module, [entry_id, linked_entry_id])
    if module == Brando.Pages.Fragment, do: resync_embedding([entry_id, linked_entry_id])

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
  Called when two entries are unlinked. The synchronized translations that
  embed a fragment that was one of them re-sync, so a fragment block that
  took the unlinked version goes back to the source's fragment.
  """
  def alternate_removed(Brando.Pages.Fragment, entry_id, linked_entry_id),
    do: resync_embedding([entry_id, linked_entry_id])

  def alternate_removed(_module, _entry_id, _linked_entry_id), do: :ok

  # A new version of an entry may be the one a translation's parent (or a
  # fragment's page) waited for. The awaiting item names that entry
  # (`parent/12`), so only its waiters re-sync: of every synchronized schema
  # with a tree relation to `module`.
  defp resync_waiting_tree(module, entry_ids) do
    waiting =
      for type <- Repo.all(from(m in Member, distinct: true, select: m.entry_type)),
          schema = known_schema(type),
          schema && synchronized?(schema),
          {name, ^module} <- Sync.tree_targets(schema),
          id <- entry_ids,
          do: {type, "#{name}/#{id}"}

    for {type, paths} <- Enum.group_by(waiting, &elem(&1, 0), &elem(&1, 1)) do
      from(w in WorkItem,
        join: v in assoc(w, :pending_version),
        join: m in assoc(v, :member),
        where: w.kind == :awaiting_translation and v.status == :pending and is_nil(w.resolved_at),
        where: w.path in ^paths and m.entry_type == ^type,
        distinct: true,
        select: m.group_id
      )
      |> Repo.all()
      |> Enum.each(&enqueue_sync(&1, false))
    end

    :ok
  end

  # A fragment's new version is the one the translations of the entries
  # embedding it take in their blocks: their groups re-sync.
  defp resync_embedding(fragment_ids) do
    blocks = Repo.all(from b in Brando.Content.Block, where: b.fragment_id in ^fragment_ids, select: b.id)

    for {schema, ids} <-
          blocks
          |> Brando.Content.BlockReferences.list_root_block_ids_by_source()
          |> Brando.Content.BlockReferences.list_entry_ids_for_root_blocks_by_source(),
        synchronized?(schema),
        group_id <-
          Repo.all(
            from m in Member,
              where: m.entry_type == ^entry_type(schema) and m.entry_id in ^ids and m.role == :source,
              select: m.group_id
          ) do
      enqueue_sync(group_id, false)
    end

    :ok
  end

  defp known_schema(type) do
    module = String.to_existing_atom(type)
    if Code.ensure_loaded?(module), do: module
  rescue
    ArgumentError -> nil
  end

  @doc """
  Replaces a member's pending version with `result`.

  Unresolved work items of the previous version are carried over when their
  path still exists and the new computation did not raise its own item for it.
  A `:review` item raised again for a path whose review is still open keeps
  the open one's `source_previous`, nil included: the text the translation
  was written from, not the source's text in between.
  Nothing is recorded when the result changes nothing and no work carries over.
  """
  def record_pending(member, result, previous, generation, schema) do
    result = %{result | work_items: keep_previous_texts(result.work_items, previous)}
    new_paths = MapSet.new(result.work_items, & &1.path)

    carried =
      case previous do
        nil ->
          []

        # Text work is carried: review is found against the baseline, which
        # this sync advances, and a translate item's path holds the source's
        # text once the version is saved, so neither would be found again.
        # Shared updates and waiting links are recomputed from the current
        # values each time; a carried one could claim a change that no longer
        # exists.
        %PendingVersion{work_items: items} ->
          for item <- items,
              item.kind in [:review, :translate],
              is_nil(item.resolved_at),
              MapSet.member?(result.paths, item.path),
              not MapSet.member?(new_paths, item.path),
              do: Map.take(item, @item_fields)
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

  defp keep_previous_texts(items, nil), do: items

  defp keep_previous_texts(items, %PendingVersion{work_items: open}) do
    reviews = for %{kind: :review, resolved_at: nil} = item <- open, into: %{}, do: {item.path, item.source_previous}

    Enum.map(items, fn
      %{kind: :review, path: path} = item when is_map_key(reviews, path) -> %{item | source_previous: reviews[path]}
      item -> item
    end)
  end

  # The text paths still to translate whose text in the translation is a copy
  # of the source's (`Sync.compute_pending/4`'s `:untranslated`): open
  # `:translate` work whose text is one the translation was given to
  # translate. Every such text was raised as a `:translate` item against its
  # digest; usually it is the source's text as of the last sync (as created,
  # or saved unchanged), else an earlier one (the source changed it again, or
  # the editor saved a version computed before). Text written past the
  # editor, which resolves nothing, is the translation's own.
  defp untranslated(_member, _schema, _target, nil, _uids), do: MapSet.new()

  defp untranslated(member, schema, target, %PendingVersion{work_items: items}, uids) do
    case for(%{kind: :translate, resolved_at: nil, path: path} <- items, uniq: true, do: path) do
      [] ->
        MapSet.new()

      open ->
        held = for {path, value} <- texts(target, schema, uids), path in open, into: %{}, do: {path, Sync.digest(value)}
        {copies, rest} = Enum.split_with(Map.keys(held), &(held[&1] == member.baseline[&1]))
        seeded = seeded_digests(member.id, rest)
        MapSet.new(copies ++ Enum.filter(rest, &MapSet.member?(seeded, {&1, held[&1]})))
    end
  end

  defp seeded_digests(_member_id, []), do: MapSet.new()

  defp seeded_digests(member_id, paths) do
    from(w in WorkItem,
      join: v in PendingVersion,
      on: v.id == w.pending_version_id,
      where: v.member_id == ^member_id and w.kind == :translate and w.path in ^paths,
      distinct: true,
      select: {w.path, w.source_digest}
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp texts(entry, schema, uids),
    do: for({path, :text, value} <- Sync.flatten_entry(entry, schema, nil, uids), into: %{}, do: {path, value})

  @doc "Returns the pending version of an entry with its work items, or nil."
  def get_pending_version(schema, entry_id) do
    case get_member(schema, entry_id) do
      nil -> nil
      member -> current_pending(member.id)
    end
  end

  @doc """
  Decodes a pending version's payload into the entry struct. A var stored as
  `html` (before brando_225) comes back as `rich_text`, as the entry has it.
  """
  def decode_payload(%PendingVersion{payload: payload}),
    do: payload |> :erlang.binary_to_term([:safe]) |> Brando.Content.Var.Type.rename_in()

  @doc """
  A pending version's content for `entry`, the translation it was computed
  for, as its form loads it. The fields the trash obfuscates (a page's `uri`)
  stay as `entry` has them when either is in the trash: a version taken
  before the trash holds the names it freed, which another entry may have
  taken since, and one taken in the trash holds their trash form. A new
  gallery ref gets a copy of its gallery (`Sync.own_new_ref_galleries/1`).
  """
  def pending_content(%PendingVersion{} = version, entry) do
    payload = version |> decode_payload() |> Sync.own_new_ref_galleries()

    case obfuscated_fields(entry) do
      [] -> payload
      _fields when is_nil(entry.deleted_at) and is_nil(payload.deleted_at) -> payload
      fields -> struct(payload, Map.take(entry, fields))
    end
  end

  defp obfuscated_fields(%schema{}) do
    if schema.has_trait(Brando.Trait.SoftDelete),
      do: Keyword.get(schema.__trait__(Brando.Trait.SoftDelete), :obfuscated_fields, []),
      else: []
  end

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
  Whether a synchronized translation of the source `id` is in the trash: it
  still counts for `guard_delete/2` until it is restored or purged, though the
  listing does not show it.
  """
  def trashed_synchronized_targets?(module, id) do
    case get_member(module, id) do
      %Member{role: :source, group_id: group_id} ->
        ids =
          Repo.all(
            from m in Member,
              where: m.group_id == ^group_id and m.role == :target and m.synchronized == true,
              select: m.entry_id
          )

        trashed_ids(module, ids) != []

      _ ->
        false
    end
  end

  @doc """
  Takes entries of `schema` deleted for good out of their groups: their
  members go, with their pending versions and work items, and their languages
  are free again. A source's group goes with it; `guard_delete/2` lets a source
  go only when no synchronized translation is left, and the independent ones
  stay as they are, outside any group. An entry in the trash keeps its member.

  The trash's purge calls it in its transaction, before the rows go; a delete
  of an entry without a trash, once the entry is gone.
  """
  def entries_deleted(_schema, []), do: :ok

  def entries_deleted(schema, ids) do
    if synchronized?(schema) do
      type = entry_type(schema)
      members = from(m in Member, where: m.entry_type == ^type and m.entry_id in ^ids)
      groups = Repo.all(from m in members, where: m.role == :source, select: m.group_id)

      Repo.delete_all(members)
      Repo.delete_all(from g in Group, where: g.id in ^groups)
    end

    :ok
  end

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

  # The pending version the editor applies must have been computed against
  # the target as it is now. A save outside the form (a published revision, a
  # scheduled release, an API update) queues a recompute, but the editor may
  # open before it runs, and the old payload would overwrite that save.
  defp fresh_pending(schema, member) do
    case current_pending(member.id) do
      %PendingVersion{base_fingerprint: base} = pending ->
        if stale_base?(schema, member, base) do
          resync_target(member.group_id, member.id)
          current_pending(member.id)
        else
          pending
        end

      nil ->
        nil
    end
  end

  @doc """
  Whether pending version `version_id` of the translation `entry_id` was
  computed from the translation as it is saved now. False once the
  translation was saved since (from the listing, by a proposal): the
  version's copy of the translation's own values is then older than what is
  saved.
  """
  def pending_base_current?(schema, entry_id, version_id) do
    with %Member{} = member <- get_member(schema, entry_id),
         base when is_binary(base) <-
           Repo.one(
             from v in PendingVersion,
               where: v.id == ^version_id and v.member_id == ^member.id,
               select: v.base_fingerprint
           ) do
      not stale_base?(schema, member, base)
    else
      _ -> false
    end
  end

  defp stale_base?(schema, member, base) do
    case load_entry(schema, member.entry_id) do
      {:ok, target} -> Sync.base_fingerprint(target, schema, module_uids([target], schema)) != base
      _ -> false
    end
  end

  defp current_pending(member_id) do
    Repo.one(
      from v in PendingVersion,
        where: v.member_id == ^member_id and v.status == :pending,
        preload: [:work_items]
    )
  end

  # The reviews still open in a group whose source moved are read against the
  # new source: the former source's text before the change is not its before
  defp forget_previous_texts(group_id) do
    versions =
      from(v in PendingVersion,
        join: m in Member,
        on: m.id == v.member_id,
        where: m.group_id == ^group_id and v.status == :pending,
        select: v.id
      )

    from(w in WorkItem,
      where: w.pending_version_id in subquery(versions) and w.kind == :review and is_nil(w.resolved_at),
      where: not is_nil(w.source_previous)
    )
    |> Repo.update_all(set: [source_previous: nil])
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

  # A version in the trash still holds its language, so a restore puts it back
  # in its group as it was; it is refused apart, so the editor is told where
  # the version is.
  defp ensure_language_free(schema, %Member{group_id: group_id}, language) do
    case Repo.one(from m in Member, where: m.group_id == ^group_id and m.language == ^language, select: m.entry_id) do
      nil ->
        :ok

      entry_id ->
        if entry_id in trashed_ids(schema, [entry_id]), do: {:error, :language_in_trash}, else: {:error, :language_exists}
    end
  end

  @doc "The ids of `ids` whose entries are in the trash."
  def trashed_ids(schema, ids) do
    if ids != [] and :deleted_at in schema.__schema__(:fields) do
      Repo.all(from e in schema, where: e.id in ^ids and not is_nil(e.deleted_at), select: e.id)
    else
      []
    end
  end

  # An independent alternate isn't a group member, but it holds its language:
  # a second version beside it would give the source two in one language.
  # Checked before the source is enrolled, so a refusal leaves no group behind.
  # A target is left to `source_member/3`, which refuses it as `:not_source`.
  defp ensure_no_linked_version(schema, entry_id, language) do
    case get_member(schema, entry_id) do
      %Member{role: :target} -> :ok
      _ -> if language in alternate_languages(schema, entry_id), do: {:error, :language_exists}, else: :ok
    end
  end

  # An entry with the source's `matched_by` values in `language`, linked to it
  # or not, is its version there: a translation beside it would give the
  # language two entries with the same keys.
  defp ensure_no_unlinked_version(schema, source_id, language) do
    with %{} = source <- Repo.get(schema, source_id),
         %Ecto.Query{} = query <- same_values_query(schema, source),
         true <- exists?(from e in query, where: e.language == ^language) do
      {:error, :language_exists}
    else
      _ -> :ok
    end
  end

  defp exclude_deleted(query, schema) do
    if :deleted_at in schema.__schema__(:fields),
      do: where(query, [_alternate, entry], is_nil(entry.deleted_at)),
      else: query
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

    slug_fields = slug_changes(schema, language)

    # Related entries a schema's own duplicate copies along (a page's child
    # pages and fragments) are separate entries, each translated on its own:
    # copied here they'd join the translation in the source's language.
    separate =
      for %{type: :has_many, name: name, opts: opts} <- Brando.Blueprint.Relations.__relations__(schema),
          opts[:module] not in [:blocks, :alternates],
          opts[:cast] != true,
          do: {name, []}

    # A context's duplicate marks a copy ("Title (copy)"); a translation starts
    # from the source's own text instead. Slugs are handled above.
    slug_names = Enum.map(slug_fields, &elem(&1, 0))

    kept_text =
      for %{name: name, type: type} <- Brando.Blueprint.Attributes.__attributes__(schema),
          type in [:string, :text],
          name not in slug_names,
          do: {name, fn _entry, value -> value end}

    # An `always_source_controlled` relation to another schema's entry (a
    # fragment's page): its version in the copy's language, or, until there is one, none
    # (the first sync marks it awaited), or the source's when it is required.
    # A page's parent is copied as it is; the first sync maps it.
    required = required_relations(schema)

    tree =
      for {name, module} <- Sync.tree_targets(schema),
          module != schema,
          field <- [
            {name, nil},
            {:"#{name}_id", fn _entry, id -> copy_tree_id(id, module, language, name in required) end}
          ],
          do: field

    override_opts = [
      change_fields:
        [{:language, String.to_existing_atom(language)} | slug_fields] ++
          kept_text ++ separate ++ tree ++ free_unique_values(schema),
      merge_change_fields: true,
      keep_sync_uid: true
    ]

    # The source among its own related entries is linked as the copy, once
    # the copy exists: a batch of one (`copy_batch_to_language/5`).
    source_id = cast_entry_id(schema, source_id)
    batch = batch_identifiers(schema, [source_id], language)
    override_opts = override_opts ++ [map_entries: &related_in_language(&1, language, MapSet.new(Map.keys(batch)))]

    with {:ok, copy} <- apply(context, :"duplicate_#{singular}", [source_id, actor, override_opts]) do
      link_batch_copies(schema, %{source_id => copy.id}, batch)
      {:ok, copy}
    end
  end

  defp copy_tree_id(nil, _module, _language, _required), do: nil

  defp copy_tree_id(id, module, language, required) do
    case version_in_language(module, id, language) do
      nil when required -> id
      version -> version
    end
  end

  defp required_relations(schema),
    do:
      for(
        %{type: :belongs_to, name: name, opts: %{required: true}} <- Brando.Blueprint.Relations.__relations__(schema),
        do: name
      )

  @doc """
  The `change_fields` that give a copy into `language` its slugs. A slug
  unique per language (`unique: [prevent_collision: :language]`, or a `with:`
  scope that includes `:language`) keeps the source's value; any other slug
  gets the language appended (`banzha` becomes `banzha-en`). A value the
  language already uses is numbered by `free_unique_values/1`.
  """
  @spec slug_changes(module(), String.t() | atom()) :: keyword()
  def slug_changes(schema, language) do
    for %{name: name, opts: opts} <- schema.__slug_fields__() do
      if Brando.Blueprint.UniqueFields.language_scoped?(opts[:unique]),
        do: {name, fn _entry, value -> value end},
        else: {name, fn _entry, value -> Utils.slugify("#{value}-#{language}") end}
    end
  end

  @doc """
  Duplicate options for copying an entry into `language`, besides its
  `change_fields`: the copy's related entries (`:entries` relations, its
  subform rows' included) point at their versions in `language`, and one
  with no version in it yet is left out. A relation the entry's own
  `change_fields` name is left to them. Later changes to the source's related
  entries are not synchronized.
  """
  @spec language_copy_opts(String.t() | atom()) :: keyword()
  def language_copy_opts(language) do
    language = to_string(language)
    [map_entries: &related_in_language(&1, language)]
  end

  @doc """
  Copies the entries of `schema` with `ids` into `language`, each with
  `override_opts` and `language_copy_opts/1`, as the listing's "Duplicate
  selected to a language" does.

  A related entry copied in the same batch is linked as its copy. One with no
  version in `language` that was not copied with it is left out, and counted.
  Returns the ids that could not be copied, each with its error, and the
  number of links left out.
  """
  @spec copy_batch_to_language(module(), [integer() | String.t()], String.t() | atom(), term(), keyword()) ::
          %{failed: [{term(), term()}], dropped_links: non_neg_integer()}
  def copy_batch_to_language(schema, ids, language, actor, override_opts) do
    language = to_string(language)
    ids = Enum.map(ids, &cast_entry_id(schema, &1))
    batch = batch_identifiers(schema, ids, language)

    {copies, failed, dropped, raised} = copy_each(schema, ids, language, actor, override_opts, batch)

    case raised do
      nil ->
        %{failed: Enum.reverse(failed), dropped_links: dropped + link_batch_copies(schema, copies, batch)}

      # The copies made so far are saved, so their links are put right even
      # when a later copy raised; the error that stopped the batch goes on.
      {kind, reason, stacktrace} ->
        links =
          try do
            "#{dropped + link_batch_copies(schema, copies, batch)} link(s) were left out of the copies made"
          catch
            link_kind, link_reason ->
              "Their links could not be put right (#{Exception.format_banner(link_kind, link_reason)}) in the copies made"
          end

        Logger.error(
          "(!) Copying #{inspect(schema)} entries to #{language} stopped at an error. " <>
            "#{links}: #{inspect(Map.values(copies))}. Not copied: #{inspect(Enum.map(failed, &elem(&1, 0)))}"
        )

        :erlang.raise(kind, reason, stacktrace)
    end
  end

  # An id as the schema's primary key: the listing sends strings for UUIDs.
  defp cast_entry_id(schema, id) do
    case Ecto.Type.cast(schema.__schema__(:type, :id), id) do
      {:ok, id} -> id
      :error -> id
    end
  end

  # The identifiers of the batch's entries that have no version in `language`,
  # each to its entry: links to those are linked to their copies once the
  # batch is copied. Identifiers name integer ids only.
  defp batch_identifiers(schema, ids, language) do
    if schema.__schema__(:type, :id) in [:id, :integer] do
      from(i in Identifier, where: i.schema == ^schema and i.entry_id in ^Enum.filter(ids, &is_integer/1))
      |> Repo.all()
      |> Enum.filter(&is_nil(counterpart_id(&1, language)))
      |> Map.new(&{&1.id, &1.entry_id})
    else
      %{}
    end
  end

  # Each entry's copy, the source id to the copy's id. A link to an entry of
  # the batch is kept as it is until the batch is copied.
  defp copy_each(schema, ids, language, actor, override_opts, batch) do
    duplicate = :"duplicate_#{schema.__naming__().singular}"
    context = schema.__modules__().context
    kept = batch |> Map.keys() |> MapSet.new()

    Enum.reduce_while(ids, {%{}, [], 0, nil}, fn id, {copies, failed, dropped, nil} ->
      counter = :counters.new(1, [])
      opts = override_opts ++ [map_entries: &related_in_language(&1, language, kept, counter)]

      try do
        case apply(context, duplicate, [id, actor, opts]) do
          {:ok, copy} -> {:cont, {Map.put(copies, id, copy.id), failed, dropped + :counters.get(counter, 1), nil}}
          error -> {:cont, {copies, [{id, error} | failed], dropped, nil}}
        end
      catch
        kind, reason -> {:halt, {copies, failed, dropped, {kind, reason, __STACKTRACE__}}}
      end
    end)
  end

  # The copies' links that still name an entry of the batch, at any depth, now
  # name its copy. A link to an entry that has no copy, or whose copy has no
  # identifier, is removed. Returns the number removed.
  defp link_batch_copies(_schema, copies, batch) when map_size(batch) == 0 or map_size(copies) == 0, do: 0

  defp link_batch_copies(schema, copies, batch) do
    for {join, row_id, identifier_id} <- batch_links(schema, Map.values(copies), Map.keys(batch)), reduce: 0 do
      removed ->
        query = from j in join, where: j.id == ^row_id

        case copies[batch[identifier_id]] && identifier_id_for(schema, copies[batch[identifier_id]]) do
          nil ->
            Repo.delete_all(query)
            removed + 1

          copy_identifier_id ->
            Repo.update_all(query, set: [identifier_id: copy_identifier_id])
            removed
        end
    end
  end

  # The `:entries` join rows naming one of `identifier_ids` that the entries of
  # `module` with `ids` hold, and their subform rows at any depth, read from
  # the database: a context's duplicate may return its copy without them.
  defp batch_links(module, ids, identifier_ids, seen \\ MapSet.new())

  defp batch_links(_module, [], _identifier_ids, _seen), do: []

  defp batch_links(module, ids, identifier_ids, seen) do
    ids = Enum.reject(ids, &MapSet.member?(seen, {module, &1}))
    seen = Enum.reduce(ids, seen, &MapSet.put(&2, {module, &1}))

    Enum.flat_map(Brando.Blueprint.Relations.__relations__(module), fn
      %{type: :entries, name: name} ->
        %{related: join, related_key: key} = module.__schema__(:association, name)

        from(j in join,
          where: field(j, ^key) in ^ids and j.identifier_id in ^identifier_ids,
          select: {j.id, j.identifier_id}
        )
        |> Repo.all()
        |> Enum.map(fn {id, identifier_id} -> {join, id, identifier_id} end)

      %{type: type, name: name, opts: %{cast: true}} when type in [:has_many, :has_one] ->
        %{related: child, related_key: key} = module.__schema__(:association, name)

        if ids != [] and Brando.Blueprint.blueprint?(child) do
          child_ids = Repo.all(from c in child, where: field(c, ^key) in ^ids, select: c.id)
          batch_links(child, child_ids, identifier_ids, seen)
        else
          []
        end

      _relation ->
        []
    end)
  end

  @doc """
  `change_fields` for copying an entry of `schema` into another language.

  Each unique text value (a page's URI, a slug, a form's key) stays as it is
  when the copy's language has it free, and is otherwise numbered: a Norwegian
  copy of the English `index` page becomes `index-2` when a Norwegian page is
  already at `index`. Put these after the language and any other change to the
  same fields: each one checks the value those leave.
  """
  def free_unique_values(schema) do
    for %{name: name, opts: %{unique: unique}} <- Brando.Blueprint.Attributes.__attributes__(schema),
        unique not in [nil, false] do
      # The entry is still the source here: its own row counts as taken.
      {name,
       fn
         entry, value when is_binary(value) -> Unique.free_value(schema, name, value, Map.put(entry, :id, nil))
         _entry, value -> value
       end}
    end
  end

  ## Saving answered work

  @doc """
  The changeset that saves `texts` (`%{path => text}`, paths as
  `Brando.Translations.Sync` flattens them) into the synchronized
  translation `entry_id`, as its form builds one: the saved translation
  takes its pending version (`pending_content/2`), which carries the
  structure and media its source dictates, with the texts written at their
  paths. Nothing is written.

  Returns `{:ok, changeset, version_id}`, `version_id` being the pending
  version the changeset was built from (nil when the translation has none:
  the texts are written into the saved translation), or `{:error, reason}`:
  `:not_translation` for an entry that is not a synchronized translation,
  `:not_found`, `:unbuildable` when the version cannot be put into a
  changeset whole (a block whose module no longer matches it).
  """
  def work_changeset(schema, entry_id, texts, user) do
    with %{member: %Member{role: :target, synchronized: true}, pending: pending} <- editor_state(schema, entry_id),
         {:ok, saved} <- load_entry(schema, entry_id, with_deleted: true) do
      payload = if pending, do: pending_content(pending, saved), else: saved
      payload = Sync.put_entry_texts(payload, schema, texts, module_uids([payload], schema))

      case payload_changeset(schema, saved, payload, user) do
        {:ok, changeset} -> {:ok, changeset, pending && pending.id}
        :error -> {:error, :unbuildable}
      end
    else
      nil -> {:error, :not_translation}
      %{} -> {:error, :not_translation}
      _ -> {:error, :not_found}
    end
  end

  # The pending version as the translation form restores it
  # (`BrandoAdmin.Components.Form.Translation.restore_changeset/1`): the
  # default form's fields, every block field and transformer, on top of the
  # saved translation.
  defp payload_changeset(schema, saved, payload, user) do
    blueprint = schema.__form__(:default)

    blocks =
      Map.new(blueprint.blocks, fn field ->
        {to_string(field.name), Brando.Drafts.Params.snapshot(Map.get(payload, :"entry_#{field.name}") || [])}
      end)

    transformers =
      Map.new(blueprint.transformers, fn {name, _, _} ->
        {to_string(name), Brando.Drafts.Params.snapshot(Map.get(payload, name) || [])}
      end)

    draft = %{
      format_version: 1,
      schema_version: Brando.Blueprint.Snapshot.get_current_version(schema),
      base_fingerprint: Brando.Drafts.fingerprint(saved),
      payload: %{
        "main" => BrandoAdmin.Components.Form.Drafts.main_params(schema, blueprint, Changeset.change(payload)),
        "blocks" => blocks,
        "transformers" => transformers,
        "modules" => Brando.Drafts.Modules.manifest(blocks)
      }
    }

    # A block whose module no longer matches it would be left out, and with
    # it the translation's text: refused rather than saved without it.
    case Brando.Drafts.Restore.prepare(draft, saved, schema, user, accept_conflict: true, compatible_only: true) do
      {:ok, changeset, []} -> {:ok, changeset}
      _ -> :error
    end
  end

  @doc """
  Saves answered translation work into the synchronized translation
  `entry_id` as its form saves it: `work_changeset/4` with the `texts`,
  `check_target_save/4` against the pending version, its blocks rendered,
  the context's update
  with `editor_review: true`, then `target_saved/3` with that version and
  every answered path acknowledged, so each answered work item is resolved,
  a text rightly the same in both languages included.

  `answer` holds `texts` (`%{path => text}`) and `acknowledged` (paths kept
  as they are). Options: `:mutation`, more options for the context's update
  (`show_notification: false`, `pubsub: false`). Run it in a transaction to
  make the save and the resolution one.

  Returns `{:ok, %{entry: entry, changeset: changeset, resolved: items,
  open: count, stale: boolean}}`, `resolved` being the work items the save resolved
  (`%{path, kind, source_digest, source_previous, minor}`, for `reopen_work/3`), or
  `{:error, reason}`: those of `work_changeset/4`,
  `{:source_controlled, paths}`, or the update's error.
  """
  def save_work(schema, entry_id, answer, user, opts \\ []) do
    texts = Map.get(answer, :texts) || %{}
    acknowledged = Enum.uniq(Map.keys(texts) ++ (Map.get(answer, :acknowledged) || []))
    mutation = Keyword.merge(Keyword.get(opts, :mutation, []), editor_review: true)
    context = schema.__modules__().context
    singular = schema.__naming__().singular

    with {:ok, changeset, version_id} <- work_changeset(schema, entry_id, texts, user),
         {:ok, changeset} <- check_target_save(schema, entry_id, changeset, version_id),
         changeset = render_blocks(schema, changeset),
         open = open_items(version_id),
         {:ok, entry} <- apply(context, :"update_#{singular}", [changeset, user, mutation]),
         {:ok, result} <- target_saved(schema, entry_id, %{version_id: version_id, acknowledged: acknowledged}) do
      {:ok, Map.merge(result, %{entry: entry, changeset: changeset, resolved: resolved_items(open, schema, entry_id)})}
    end
  end

  # Rendered before it is saved, as the form renders it: the update renders
  # nothing for a changeset without a status change.
  defp render_blocks(schema, changeset) do
    if schema.__blocks_fields__() == [], do: changeset, else: Blocks.render_block_fields(changeset)
  end

  defp open_items(nil), do: []

  defp open_items(version_id),
    do: Repo.all(from(w in WorkItem, where: w.pending_version_id == ^version_id and is_nil(w.resolved_at)))

  defp resolved_items([], _schema, _entry_id), do: []

  # Each with the member that was the source when it was resolved: its
  # previous text is that source's, and is not opened again under another
  defp resolved_items(open, schema, entry_id) do
    ids = Enum.map(open, & &1.id)
    source_member_id = source_member_id(get_member(schema, entry_id))

    from(w in WorkItem, where: w.id in ^ids and not is_nil(w.resolved_at), order_by: w.id)
    |> Repo.all()
    |> Enum.map(&(&1 |> Map.take(@item_fields) |> Map.put(:source_member_id, source_member_id)))
  end

  defp source_member_id(%Member{group_id: group_id}),
    do: Repo.one(from m in Member, where: m.group_id == ^group_id and m.role == :source, select: m.id, limit: 1)

  defp source_member_id(_member), do: nil

  @doc """
  Opens again work `save_work/5` resolved, after the translation's text is
  put back (an undo): its pending version is recomputed against the saved
  translation with `items` (`%{path, kind, source_digest, source_previous, minor}`, as
  `save_work/5` returns them) open again beside the work still open. A text
  that is again the copy of the source's is to translate against the
  source's current text, as before. Where the source changed a path again
  since, the item opened again replaces the open one, against the source's
  current text, with the text it was written from. Returns
  `{:ok, open_count}`; nothing is done for an entry that is not a
  synchronized translation.
  """
  def reopen_work(schema, entry_id, items) do
    with true <- synchronized?(schema),
         %Member{role: :target, synchronized: true} = member <- get_member(schema, entry_id) do
      Repo.transaction(fn -> reopen_member_work(schema, member, items) end)
    else
      _ -> {:ok, 0}
    end
  end

  defp reopen_member_work(schema, member, items) do
    group = Repo.one!(from g in Group, where: g.id == ^member.group_id, lock: "FOR UPDATE")
    current = current_pending(member.id)
    open = if current, do: Enum.filter(current.work_items, &is_nil(&1.resolved_at)), else: []
    reopened = Enum.map(items, &reopened_item(&1, source_member_id(member)))
    previous = %{(current || %PendingVersion{member_id: member.id}) | work_items: reopen_into(open, reopened)}

    with {:ok, source} <- load_group_source(group),
         do: sync_member(schema, source, member, group.source_generation, false, previous: previous, with_deleted: true)

    open_count(member.id)
  end

  # An item resolved under another source than the group has now is opened
  # without its previous text, which is in that former source's language. An
  # item that does not say (a receipt from before it was recorded) keeps it.
  defp reopened_item(item, source_member_id) do
    {made_under, fields} = item |> atomize_item() |> Map.pop(:source_member_id)

    fields =
      if made_under && made_under != source_member_id, do: Map.put(fields, :source_previous, nil), else: fields

    struct(WorkItem, Map.put(fields, :resolved_at, nil))
  end

  # One open item per path: a path the source changed again since the work
  # was resolved keeps the reopened item, the translation being back at the
  # text it was written from, against the source's current text
  defp reopen_into(open, reopened) do
    digests = Map.new(open, &{&1.path, &1.source_digest})
    reopened_paths = MapSet.new(reopened, & &1.path)

    Enum.reject(open, &MapSet.member?(reopened_paths, &1.path)) ++
      Enum.map(reopened, &%{&1 | source_digest: Map.get(digests, &1.path, &1.source_digest)})
  end

  # As a receipt stores them: string keys, the kind a string
  defp atomize_item(%{"path" => path, "kind" => kind} = item),
    do: %{
      path: path,
      kind: String.to_existing_atom(kind),
      source_digest: item["source_digest"],
      source_previous: item["source_previous"],
      minor: item["minor"] || false,
      source_member_id: item["source_member_id"]
    }

  defp atomize_item(%{} = item), do: Map.take(item, [:source_member_id | @item_fields])

  @doc """
  Loads an entry as synchronization reads it, with every preload its
  Blueprint declares. `with_deleted: true` finds one in the trash too.
  """
  def load_entry(schema, id, opts \\ []) do
    singular = schema.__naming__().singular
    context = schema.__modules__().context
    args = %{matches: %{id: id}, preload: Brando.Blueprint.preloads_for(schema)}
    args = if opts[:with_deleted], do: Map.put(args, :with_deleted, true), else: args
    apply(context, :"get_#{singular}", [args])
  end

  defp schema_version(schema) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__schema_version__, 0),
      do: schema.__schema_version__(),
      else: 0
  end

  defp exists?(query), do: Repo.one(from(q in query, select: true, limit: 1)) == true

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
  defp naive_now, do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
end
