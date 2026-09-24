defmodule Brando.Query.Mutations do
  use Gettext, backend: Brando.Gettext

  alias Brando.Content
  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Datasource
  alias Brando.Notifications
  alias Brando.Publisher
  alias Brando.Query
  alias Brando.Revisions
  alias Brando.Tenant
  alias Brando.Tenant.Job
  alias Brando.Trait
  alias Brando.Utils
  alias Brando.Authorization.Boundary

  def create(module, params, user, callback_block, opts) do
    Boundary.run(user, :create, module, &do_create(module, params, &1, callback_block, opts))
  end

  defp do_create(module, params, user, callback_block, opts) do
    {preloads, opts} = Keyword.pop(opts, :preloads)
    {custom_changeset, opts} = Keyword.pop(opts, :changeset)
    changeset_fun = custom_changeset || (&module.changeset/5)
    notify? = Keyword.get(opts, :notify?, true)
    pubsub? = Keyword.get(opts, :pubsub?, true)

    changeset =
      module
      |> struct()
      |> changeset_fun.(params, user, nil, opts)
      |> Publisher.maybe_override_status()

    result = with :ok <- Boundary.change(user, :create, changeset), do: Query.insert(changeset)

    case result do
      {:ok, entry} ->
        {:ok, entry} = maybe_preload(entry, preloads)
        {:ok, identifier_result} = Content.create_identifier(module, entry)
        {:ok, _} = Publisher.schedule_publishing(entry, changeset, user)

        # Enqueue async cascade (merged datasource + identifier)
        identifier_id = get_identifier_id(identifier_result)
        enqueue_entry_cascade(module, entry, identifier_id)

        # Revision capture must happen before another save can replace the
        # persisted state this mutation represents.
        revisioned? = module.__trait__(Trait.Revisioned)
        {:ok, _revision} = maybe_create_revision(entry, user, revisioned?)
        maybe_notify(entry, "created", user, notify?)
        maybe_broadcast(module, entry, :created, pubsub?)

        callback_block.(entry)

      err ->
        err
    end
  end

  def create_with_changeset(module, changeset, user, callback_block, opts) do
    if changeset.data.__struct__ == module do
      Boundary.run(user, :create, module, &do_create_with_changeset(module, changeset, &1, callback_block, opts))
    else
      {:error, :forbidden}
    end
  end

  defp do_create_with_changeset(module, changeset, user, callback_block, opts) do
    {preloads, _opts} = Keyword.pop(opts, :preloads)
    notify? = Keyword.get(opts, :notify?, true)
    pubsub? = Keyword.get(opts, :pubsub?, true)

    with changeset <- Publisher.maybe_override_status(changeset),
         changeset <- set_action(changeset, :insert),
         :ok <- Boundary.change(user, :create, changeset),
         {:ok, entry} <- Query.insert(changeset),
         {:ok, entry} <- maybe_preload(entry, preloads),
         {:ok, identifier_result} <- Content.create_identifier(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      # Enqueue async cascade (merged datasource + identifier)
      identifier_id = get_identifier_id(identifier_result)
      enqueue_entry_cascade(module, entry, identifier_id)

      # Capture the exact state from this mutation synchronously.
      revisioned? = module.__trait__(Trait.Revisioned)
      {:ok, _revision} = maybe_create_revision(entry, user, revisioned?)
      maybe_notify(entry, "created", user, notify?)
      maybe_broadcast(module, entry, :created, pubsub?)

      callback_block.(entry)
    end
  end

  defp maybe_preload(entry, nil), do: {:ok, entry}
  defp maybe_preload(entry, preloads), do: {:ok, entry |> Brando.Repo.preload(preloads)}

  def update(context, module, name, id, params, opts) do
    user = Keyword.fetch!(opts, :user)
    Boundary.run(user, :update, module, &do_update(context, module, name, id, params, Keyword.put(opts, :user, &1)))
  end

  defp do_update(context, module, name, id, params, opts) do
    user = Keyword.fetch!(opts, :user)
    preloads = Keyword.get(opts, :preloads)
    callback = Keyword.get(opts, :callback, &{:ok, &1})
    custom_changeset = Keyword.get(opts, :changeset)
    notify? = Keyword.get(opts, :notify?, true)

    changeset_fun = custom_changeset || (&module.changeset/5)

    get_opts =
      if preloads do
        %{matches: %{id: id}, preload: preloads}
      else
        %{matches: %{id: id}}
      end

    with {:ok, entry} <- apply(context, :"get_#{name}", [get_opts]),
         changeset <- changeset_fun.(entry, params, user, nil, []),
         changeset <- Publisher.maybe_override_status(changeset),
         changeset <- set_action(changeset, :update),
         :ok <- Boundary.change(user, :update, changeset),
         {:ok, entry} <- Query.update(changeset),
         {:ok, identifier_result} <- Content.update_identifier(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      if has_changes(changeset) do
        # Enqueue async cascade (merged datasource + identifier)
        identifier_id = get_identifier_id(identifier_result)
        enqueue_entry_cascade(module, entry, identifier_id)

        # Capture the exact state from this mutation synchronously.
        revisioned? = module.__trait__(Trait.Revisioned)
        {:ok, _revision} = maybe_create_revision(entry, user, revisioned?)
        maybe_notify(entry, "updated", user, notify?)

        callback.(entry)
      else
        {:ok, entry}
      end
    end
  end

  def update_with_changeset(module, changeset, user, preloads, callback_block, opts) do
    if changeset.data.__struct__ == module do
      Boundary.run(
        user,
        :update,
        module,
        &do_update_with_changeset(module, changeset, &1, preloads, callback_block, opts)
      )
    else
      {:error, :forbidden}
    end
  end

  defp do_update_with_changeset(module, changeset, user, preloads, callback_block, opts) do
    notify? = Keyword.get(opts, :show_notification, true)
    pubsub? = Keyword.get(opts, :pubsub, true)

    with changeset <- Publisher.maybe_override_status(changeset),
         changeset <- set_action(changeset, :update),
         :ok <- Boundary.change(user, :update, changeset),
         {:ok, entry} <- Query.update(changeset),
         {:ok, entry} <- maybe_preload(entry, preloads),
         {:ok, identifier_result} <- Content.update_identifier(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      if has_changes(changeset) do
        # Enqueue async cascade (merged datasource + identifier)
        identifier_id = get_identifier_id(identifier_result)
        enqueue_entry_cascade(module, entry, identifier_id)

        # Capture the exact state from this mutation synchronously.
        revisioned? = module.__trait__(Trait.Revisioned)
        {:ok, _revision} = maybe_create_revision(entry, user, revisioned?)
        maybe_notify(entry, "updated", user, notify?)
        maybe_broadcast(module, entry, :updated, pubsub?)

        callback_block.(entry)
      else
        {:ok, entry}
      end
    else
      {:error, :forbidden} = err ->
        err

      err ->
        require Logger

        Logger.error("""

        update_with_changeset failed with error:
        #{inspect(err, pretty: true)}

        """)

        err
    end
  end

  def duplicate(context, module, name, id, opts) do
    user = Keyword.fetch!(opts, :user)
    Boundary.run(user, :duplicate, module, &do_duplicate(context, module, name, id, Keyword.put(opts, :user, &1)))
  end

  defp do_duplicate(context, module, name, id, opts) do
    user = Keyword.fetch!(opts, :user)
    duplicate_opts = Keyword.get(opts, :duplicate_opts, [])
    override_opts = Keyword.get(opts, :override_opts, []) |> Enum.into(%{})
    preloads = Keyword.get(duplicate_opts, :preload) || Brando.Blueprint.preloads_for(module)

    with {:ok, entry} <- apply(context, :"get_#{name}", [%{matches: %{id: id}, preload: preloads}]),
         :ok <- Boundary.authorize(user, :read, entry),
         :ok <- Boundary.authorize(user, :duplicate, entry),
         :ok <- Boundary.authorize(user, :create, module) do
      merged_opts =
        duplicate_opts
        |> Enum.into(%{})
        |> Map.merge(override_opts)
        |> maybe_merge_change_fields(duplicate_opts, override_opts)

      has_blocks? = module.has_trait(Trait.Blocks)

      cloned_entry =
        entry
        |> maybe_change_fields(merged_opts)
        |> maybe_delete_fields(merged_opts)
        |> maybe_set_status()
        |> maybe_duplicate_blocks(module, has_blocks?, Map.get(merged_opts, :keep_sync_uid, false))
        |> maybe_merge_fields(merged_opts)
        |> maybe_put_creator(user)
        |> detach_has_many(module)
        |> drop_fields()
        |> update_meta()

      with :ok <- Boundary.change(user, :create, Ecto.Changeset.change(cloned_entry)),
           {:ok, cloned_entry} <- clone_galleries(cloned_entry, module, user),
           do: Brando.Repo.insert(cloned_entry)
    end
  end

  # A loaded `has_many` row that still has its id would be re-pointed at the
  # copy on insert — the original entry loses it. Rows the entry owns (subform
  # relations with `cast: true`) are copied, keeping everything but their id and
  # foreign key, so a row `uid` still pairs it with the original. Rows it merely
  # links to, like alternates, are dropped. Rows a `change_fields` handler has
  # already built (nil id) are left alone.
  defp detach_has_many(entry, module) do
    owned =
      for %{type: :has_many, name: name, opts: %{cast: true}} <- Brando.Blueprint.Relations.__relations__(module),
          do: name

    Enum.reduce(module.__schema__(:associations), entry, fn name, acc ->
      case {module.__schema__(:association, name), Map.get(acc, name)} do
        {%Ecto.Association.Has{cardinality: :many, related_key: related_key}, rows} when is_list(rows) ->
          Map.put(acc, name, detach_rows(rows, related_key, name in owned))

        {%Ecto.Association.HasThrough{cardinality: :many}, rows} when is_list(rows) ->
          Map.put(acc, name, [])

        _ ->
          acc
      end
    end)
  end

  defp detach_rows(rows, related_key, owned?) do
    Enum.flat_map(rows, fn
      %{id: nil} = row -> [row]
      row when owned? -> [row |> Map.merge(%{:id => nil, related_key => nil}) |> update_meta()]
      _row -> []
    end)
  end

  # A gallery belongs to the ref, var or asset that points at it — see
  # `Brando.Content.Blocks.duplicate_ref/2`. A copy that kept the original's
  # `gallery_id` would edit the original's gallery, and for a translation that
  # means changing a published page behind the editor's back.
  defp clone_galleries(entry, module, user) do
    gallery_ids = entry |> gallery_ids(module) |> Enum.uniq()

    Enum.reduce_while(gallery_ids, {:ok, %{}}, fn gallery_id, {:ok, clones} ->
      case Brando.Galleries.duplicate_gallery(gallery_id, user) do
        {:ok, gallery} -> {:cont, {:ok, Map.put(clones, gallery_id, gallery)}}
        {:error, reason} -> {:halt, {:error, {:gallery, gallery_id, reason}}}
      end
    end)
    |> case do
      {:ok, clones} when map_size(clones) == 0 -> {:ok, entry}
      {:ok, clones} -> {:ok, put_galleries(entry, module, clones)}
      error -> error
    end
  end

  defp gallery_ids(entry, module) do
    asset_ids = for name <- gallery_assets(module), id = Map.get(entry, :"#{name}_id"), do: id
    asset_ids ++ Enum.flat_map(gallery_holders(entry, module), &holder_gallery_ids/1)
  end

  defp holder_gallery_ids(%{gallery_id: id}) when not is_nil(id), do: [id]
  defp holder_gallery_ids(_), do: []

  defp put_galleries(entry, module, clones) do
    entry =
      Enum.reduce(gallery_assets(module), entry, fn name, acc ->
        case clones[Map.get(acc, :"#{name}_id")] do
          nil -> acc
          gallery -> acc |> Map.put(:"#{name}_id", gallery.id) |> Map.put(name, gallery)
        end
      end)

    map_gallery_holders(entry, module, fn
      %{gallery_id: id} = holder when is_map_key(clones, id) ->
        %{holder | gallery_id: clones[id].id, gallery: clones[id]}

      holder ->
        holder
    end)
  end

  defp gallery_assets(module) do
    for %{type: :gallery, name: name} <- Brando.Blueprint.Assets.__assets__(module), do: name
  end

  # Refs and vars inside blocks, table rows and entry-level var relations.
  defp gallery_holders(entry, module) do
    {_, holders} = map_gallery_holders(entry, module, fn holder -> holder end, [])
    holders
  end

  defp map_gallery_holders(entry, module, fun) do
    {entry, _} = map_gallery_holders(entry, module, fun, [])
    entry
  end

  defp map_gallery_holders(entry, module, fun, acc) do
    block_fields =
      if module.has_trait(Trait.Blocks), do: Enum.map(module.__blocks_fields__(), &:"entry_#{&1.name}"), else: []

    var_fields =
      for %{type: :has_many, name: name, opts: %{module: Brando.Content.Var}} <-
            Brando.Blueprint.Relations.__relations__(module),
          do: name

    {entry, acc} =
      Enum.reduce(block_fields, {entry, acc}, fn field, {entry, acc} ->
        {joins, acc} =
          Enum.map_reduce(loaded_list(Map.get(entry, field)), acc, fn join, acc ->
            {block, acc} = map_block_galleries(join.block, fun, acc)
            {%{join | block: block}, acc}
          end)

        {Map.put(entry, field, joins), acc}
      end)

    Enum.reduce(var_fields, {entry, acc}, fn field, {entry, acc} ->
      {vars, acc} = map_holders(Map.get(entry, field), fun, acc)
      {Map.put(entry, field, vars), acc}
    end)
  end

  defp map_block_galleries(block, fun, acc) do
    {refs, acc} = map_holders(block.refs, fun, acc)
    {vars, acc} = map_holders(block.vars, fun, acc)

    {rows, acc} =
      Enum.map_reduce(loaded_list(block.table_rows), acc, fn row, acc ->
        {vars, acc} = map_holders(row.vars, fun, acc)
        {%{row | vars: vars}, acc}
      end)

    {children, acc} = Enum.map_reduce(loaded_list(block.children), acc, &map_block_galleries(&1, fun, &2))
    {%{block | refs: refs, vars: vars, table_rows: rows, children: children}, acc}
  end

  defp map_holders(holders, fun, acc) do
    Enum.map_reduce(loaded_list(holders), acc, fn holder, acc -> {fun.(holder), [holder | acc]} end)
  end

  defp loaded_list(list) when is_list(list), do: list
  defp loaded_list(_), do: []

  # Override `change_fields` replace the context's by default. With
  # `merge_change_fields: true` the context's handlers are kept for every field
  # the override does not name — a copy that must still clone its subform rows.
  defp maybe_merge_change_fields(merged, duplicate_opts, %{merge_change_fields: true, change_fields: overrides}) do
    overridden = Enum.map(overrides, &change_field_name/1)

    kept =
      duplicate_opts
      |> Map.new()
      |> Map.get(:change_fields, [])
      |> Enum.reject(&(change_field_name(&1) in overridden))

    Map.put(merged, :change_fields, kept ++ overrides)
  end

  defp maybe_merge_change_fields(merged, _duplicate_opts, _override_opts), do: merged

  defp change_field_name({name, _}), do: name
  defp change_field_name(name), do: name

  defp maybe_put_creator(%{creator_id: _} = entry, %{id: user_id}) do
    Map.put(entry, :creator_id, user_id)
  end

  defp maybe_put_creator(entry, _user), do: entry

  defp update_meta(struct) do
    put_in(struct, [Access.key(:__meta__), Access.key(:state)], :built)
  end

  defp drop_fields(%{id: _} = entry), do: Utils.nilify_fields(entry, [:id, :inserted_at, :updated_at])
  defp drop_fields(entry), do: entry

  defp maybe_set_status(%{status: _} = entry), do: Map.put(entry, :status, :draft)
  defp maybe_set_status(entry), do: entry

  # `keep_sync_uid: true` makes the copy a synchronized translation of the
  # original (`Brando.Translations.create_target/4`): each block and table row
  # keeps the identity that pairs it with its source counterpart. An ordinary
  # duplicate is independent and gets fresh identities.
  defp maybe_duplicate_blocks(entry, module, true, keep_sync_uid?) do
    block_fields = Enum.map(module.__blocks_fields__(), &:"entry_#{&1.name}")

    updated_entry =
      Enum.reduce(block_fields, entry, fn field, acc ->
        blocks = Map.get(acc, field)

        duplicated_blocks =
          Enum.map(blocks, fn entry_block ->
            entry_block = %{entry_block | id: nil, entry_id: nil, block_id: nil}
            entry_block = update_meta(entry_block)
            updated_block = duplicate_block(entry_block.block, keep_sync_uid?)
            %{entry_block | block: updated_block}
          end)

        Map.put(acc, field, duplicated_blocks)
      end)

    updated_entry
  end

  defp maybe_duplicate_blocks(entry, _module, false, _keep_sync_uid?), do: entry

  @doc false
  def duplicate_block(block, keep_sync_uid?) do
    %{
      block
      | id: nil,
        uid: Brando.Utils.generate_uid(),
        sync_uid: if(keep_sync_uid?, do: block.sync_uid || block.uid),
        vars: Enum.map(block.vars || [], &duplicate_var/1),
        table_rows: Enum.map(block.table_rows || [], &duplicate_table_row(&1, keep_sync_uid?)),
        block_identifiers: Enum.map(block.block_identifiers || [], &duplicate_block_identifiers/1),
        children: Enum.map(block.children || [], &duplicate_block(&1, keep_sync_uid?)),
        refs: duplicate_refs(block.refs || []),
        creator: nil,
        fragment: nil,
        module: nil,
        identifiers: nil
    }
    |> update_meta()
  end

  defp duplicate_table_row(table_row, keep_sync_uid?) do
    sync_uid = if keep_sync_uid? && table_row.sync_uid, do: table_row.sync_uid, else: Brando.Utils.generate_uid()

    %{table_row | id: nil, sync_uid: sync_uid, vars: Enum.map(table_row.vars || [], &duplicate_var/1)}
    |> update_meta()
  end

  defp duplicate_block_identifiers(block_identifier) do
    %{block_identifier | id: nil, block_id: nil}
    |> update_meta()
  end

  defp duplicate_var(var) do
    %{var | id: nil}
    |> update_meta()
  end

  defp duplicate_refs(refs) do
    Enum.map(refs, fn ref ->
      ref
      |> Map.merge(%{
        id: nil,
        block_id: nil,
        uid: Brando.Utils.generate_uid(),
        inserted_at: nil,
        updated_at: nil
      })
      |> update_meta()
    end)
  end

  defp maybe_change_fields(entry, %{change_fields: change_fields}) do
    Enum.reduce(change_fields, entry, fn
      {f, new_value_fun}, updated_entry when is_function(new_value_fun) ->
        current_value = Map.get(updated_entry, f)
        Map.put(updated_entry, f, new_value_fun.(updated_entry, current_value))

      {f, new_value}, updated_entry ->
        Map.put(updated_entry, f, new_value)

      f, updated_entry ->
        default_value = Map.get(updated_entry, f)
        Map.update(updated_entry, f, default_value, fn v -> "#{v}_dupl" end)
    end)
  end

  defp maybe_change_fields(entry, _), do: entry

  defp maybe_delete_fields(entry, %{delete_fields: delete_fields}) do
    unless is_list(delete_fields) do
      raise ArgumentError, message: "delete_fields must be a list"
    end

    Utils.nilify_fields(entry, delete_fields)
  end

  defp maybe_delete_fields(entry, _), do: entry

  defp maybe_merge_fields(entry, %{merge_fields: merge_fields}) do
    unless is_map(merge_fields) do
      raise ArgumentError, message: "merge_fields must be a map"
    end

    Map.merge(entry, merge_fields)
  end

  defp maybe_merge_fields(entry, _), do: entry

  defp set_action(changeset, action), do: %{changeset | action: action}

  def delete(context, module, name, id, opts) do
    user = Keyword.get(opts, :user, :system)
    Boundary.run(user, :delete, module, &do_delete(context, module, name, id, Keyword.put(opts, :user, &1)))
  end

  defp do_delete(context, module, name, id, opts) do
    user = Keyword.get(opts, :user, :system)
    preloads = Keyword.get(opts, :preloads)
    callback = Keyword.get(opts, :callback, &{:ok, &1})

    get_opts = (preloads && %{matches: %{id: id}, preload: preloads}) || %{matches: %{id: id}}

    with {:ok, entry} <- apply(context, :"get_#{name}", [get_opts]),
         :ok <- Boundary.authorize(user, :delete, entry),
         :ok <- authorize_deletion(user, entry),
         :ok <- Brando.Translations.guard_delete(module, entry),
         soft_deletable? = module.__trait__(Trait.SoftDelete),
         {:ok, entry} <-
           if(soft_deletable?,
             do: Brando.Repo.soft_delete(entry),
             else: Query.delete(entry)
           ) do
      Content.delete_identifier(module, entry)
      Datasource.update_datasource(module, entry)

      if !soft_deletable? and module.__trait__(Trait.Revisioned) do
        Revisions.delete_entry_revisions(module, entry.id)
      end

      maybe_notify(entry, "deleted", user, true)
      maybe_broadcast(module, entry, :deleted, true)

      callback.(entry)
    end
  end

  defp authorize_deletion(:system, _), do: :ok

  defp authorize_deletion(user, %{__struct__: Brando.Users.User} = entry) do
    if Brando.Authorization.enabled?(), do: Brando.Authorization.Groups.protect_account!(entry.id)
    Boundary.authorize(user, :delete, entry)
  end

  defp authorize_deletion(user, %{status: :published} = entry), do: Boundary.authorize(user, :publish, entry)
  defp authorize_deletion(_user, _entry), do: :ok

  defp has_changes(%Ecto.Changeset{changes: changes}) when map_size(changes) > 0, do: true
  defp has_changes(_), do: false

  # Post-mutation effect helpers with pattern matching to avoid nesting
  # Note: __trait__ returns false if not present, or opts list (possibly []) if present

  defp maybe_create_revision(entry, user, false) do
    Brando.MarkdownSources.Publication.entry_saved(entry, user)
    {:ok, nil}
  end

  defp maybe_create_revision(entry, user, _trait_opts) do
    with {:ok, revision} <- Revisions.create_revision(entry, user) do
      Brando.MarkdownSources.Publication.entry_saved(entry, user)
      {:ok, revision}
    end
  end

  defp maybe_notify(_entry, _action, _user, false), do: :ok

  defp maybe_notify(entry, action, user, true) do
    case Brando.Blueprint.Identifier.identifier_for(entry) do
      nil -> :ok
      identifier -> Notifications.push_mutation(Gettext.gettext(Brando.Gettext, action), identifier, user)
    end
  end

  defp maybe_broadcast(_module, _entry, _action, false), do: :ok

  defp maybe_broadcast(module, entry, action, true) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.scoped("brando:mutations:#{inspect(module)}"),
      {:mutation, module, entry, action}
    )
  end

  defp enqueue_entry_cascade(module, entry, identifier_id) do
    # Shared records can be referenced by content in any environment. At initial
    # account setup there may be no environments yet, so there is nothing to render.
    if Tenant.enabled?() && module.__schema__(:prefix) == "public" do
      Job.each_active_environment(:all, fn -> ContentBlocks.enqueue_entry_cascade(module, entry, identifier_id) end)
    else
      ContentBlocks.enqueue_entry_cascade(module, entry, identifier_id)
    end
  end

  defp get_identifier_id(%Brando.Content.Identifier{id: id}), do: id
  defp get_identifier_id(_), do: nil
end
