defmodule Brando.Query.Mutations do
  use Gettext, backend: Brando.Gettext

  alias Brando.Content
  alias Brando.Datasource
  alias Brando.Notifications
  alias Brando.Publisher
  alias Brando.Query
  alias Brando.Revisions
  alias Brando.Trait
  alias Brando.Utils

  def create(module, params, user, callback_block, opts) do
    {preloads, opts} = Keyword.pop(opts, :preloads)
    {custom_changeset, opts} = Keyword.pop(opts, :changeset)
    notify? = Keyword.get(opts, :notify?, true)
    changeset_fun = custom_changeset || (&module.changeset/5)

    changeset =
      module
      |> struct()
      |> changeset_fun.(params, user, nil, opts)
      |> Publisher.maybe_override_status()

    case Query.insert(changeset) do
      {:ok, entry} ->
        {:ok, entry} = maybe_preload(entry, preloads)
        {:ok, _} = Datasource.update_datasource(module, entry)
        {:ok, _} = Content.create_identifier(module, entry)
        {:ok, _} = Publisher.schedule_publishing(entry, changeset, user)

        revisioned? = module.__trait__(Trait.Revisioned)

        if revisioned? do
          Revisions.create_revision(entry, user)
        end

        if notify? do
          case Brando.Blueprint.Identifier.identifier_for(entry) do
            nil -> nil
            identifier -> Notifications.push_mutation(gettext("created"), identifier, user)
          end
        end

        callback_block.(entry)

      err ->
        err
    end
  end

  def create_with_changeset(module, changeset, user, callback_block, opts) do
    {preloads, _opts} = Keyword.pop(opts, :preloads)
    notify? = Keyword.get(opts, :notify?, true)

    with changeset <- Publisher.maybe_override_status(changeset),
         changeset <- set_action(changeset, :insert),
         {:ok, entry} <- Query.insert(changeset),
         {:ok, entry} <- maybe_preload(entry, preloads),
         {:ok, _} <- Datasource.update_datasource(module, entry),
         {:ok, _} <- Content.create_identifier(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      revisioned? = module.__trait__(Trait.Revisioned)

      if revisioned? do
        Revisions.create_revision(entry, user)
      end

      if notify? do
        case Brando.Blueprint.Identifier.identifier_for(entry) do
          nil -> nil
          identifier -> Notifications.push_mutation(gettext("created"), identifier, user)
        end
      end

      callback_block.(entry)
    end
  end

  defp maybe_preload(entry, nil), do: {:ok, entry}
  defp maybe_preload(entry, preloads), do: {:ok, entry |> Brando.Repo.preload(preloads)}

  def update(
        context,
        module,
        name,
        id,
        params,
        user,
        preloads,
        callback_block,
        custom_changeset,
        show_notification
      ) do
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
         {:ok, entry} <- Query.update(changeset),
         {:ok, _} <- Datasource.update_datasource(module, entry),
         {:ok, _} <- Content.update_identifier(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      if has_changes(changeset) do
        revisioned? = module.__trait__(Trait.Revisioned)

        if revisioned? do
          Revisions.create_revision(entry, user)
        end

        if show_notification do
          case Brando.Blueprint.Identifier.identifier_for(entry) do
            nil -> nil
            identifier -> Notifications.push_mutation(gettext("updated"), identifier, user)
          end
        end

        callback_block.(entry)
      else
        {:ok, entry}
      end
    else
      err ->
        err
    end
  end

  def update_with_changeset(module, changeset, user, preloads, callback_block, opts) do
    show_notification = Keyword.get(opts, :show_notification, true)

    with changeset <- Publisher.maybe_override_status(changeset),
         changeset <- set_action(changeset, :update),
         {:ok, entry} <- Query.update(changeset),
         {:ok, entry} <- maybe_preload(entry, preloads),
         {:ok, _} <- Datasource.update_datasource(module, entry),
         {:ok, _} <- Content.update_identifier(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      if has_changes(changeset) do
        revisioned? = module.__trait__(Trait.Revisioned)

        if revisioned? do
          Revisions.create_revision(entry, user)
        end

        if show_notification do
          case Brando.Blueprint.Identifier.identifier_for(entry) do
            nil -> nil
            identifier -> Notifications.push_mutation(gettext("updated"), identifier, user)
          end
        end

        callback_block.(entry)
      else
        {:ok, entry}
      end
    else
      err ->
        require Logger

        Logger.error("""

        update_with_changeset failed with error:
        #{inspect(err, pretty: true)}

        """)

        err
    end
  end

  def duplicate(context, module, name, id, opts, override_opts, user) do
    override_opts = Enum.into(override_opts, %{})
    preloads = Keyword.get(opts, :preload) || []

    case apply(context, :"get_#{name}", [%{matches: %{id: id}, preload: preloads}]) do
      {:ok, entry} ->
        opts =
          opts
          |> Enum.into(%{})
          |> Map.merge(override_opts)

        params =
          entry
          |> maybe_change_fields(opts)
          |> maybe_delete_fields(opts)
          |> maybe_set_status()
          |> maybe_duplicate_blocks(module, opts)
          |> Utils.map_from_struct()
          |> maybe_merge_fields(opts)
          |> drop_fields()

        # if the module has the Block trait, we need to cast the blocks
        create_opts = if module.has_trait(Trait.Blocks), do: [cast_blocks: true], else: []
        apply(context, :"create_#{name}", [params, user, create_opts])

      err ->
        err
    end
  end

  defp drop_fields(%{id: _} = entry), do: Map.drop(entry, [:id, :inserted_at, :updated_at])
  defp drop_fields(entry), do: entry

  defp maybe_set_status(%{status: _} = entry), do: Map.put(entry, :status, :draft)
  defp maybe_set_status(entry), do: entry

  defp maybe_duplicate_blocks(entry, module, _opts) do
    block_fields = Enum.map(module.__blocks_fields__(), &:"entry_#{&1.name}")
    preloads = Brando.Villain.preloads_for(module)
    entry = Brando.Repo.preload(entry, preloads)

    updated_entry =
      Enum.reduce(block_fields, entry, fn field, acc ->
        blocks = Map.get(acc, field)

        duplicated_blocks =
          Enum.map(blocks, fn entry_block ->
            entry_block = %{entry_block | id: nil, entry_id: nil, block_id: nil}

            updated_block = duplicate_block(entry_block.block)
            %{entry_block | block: updated_block}
          end)

        Map.put(acc, field, duplicated_blocks)
      end)

    updated_entry
  end

  defp duplicate_block(block) do
    new_uid = Brando.Utils.generate_uid()

    %{
      block
      | id: nil,
        uid: new_uid,
        vars: Enum.map(block.vars, &duplicate_var/1),
        table_rows: Enum.map(block.table_rows, &%{&1 | id: nil}),
        block_identifiers: Enum.map(block.block_identifiers, &%{&1 | id: nil, block_id: nil}),
        children: Enum.map(block.children, &duplicate_block/1),
        refs: duplicate_refs(block.refs)
    }
  end

  defp duplicate_var(var) do
    %{var | id: nil}
  end

  defp duplicate_refs(refs) do
    refs
    |> get_and_update_in(
      [Access.all(), Access.key(:data), Access.key(:uid)],
      &{&1, Brando.Utils.generate_uid()}
    )
    |> elem(1)
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

    Map.drop(entry, delete_fields)
  end

  defp maybe_delete_fields(entry, _), do: entry

  defp maybe_merge_fields(entry, %{merge_fields: merge_fields}) do
    unless is_map(merge_fields) do
      raise ArgumentError, message: "merge_fields must be a list"
    end

    Map.merge(entry, merge_fields)
  end

  defp maybe_merge_fields(entry, _), do: entry

  defp set_action(changeset, action), do: %{changeset | action: action}

  def delete(context, module, name, id, user, preloads, callback_block) do
    get_opts = (preloads && %{matches: %{id: id}, preload: preloads}) || %{matches: %{id: id}}

    {:ok, entry} = apply(context, :"get_#{name}", [get_opts])
    soft_deletable? = module.__trait__(Trait.SoftDelete)

    {:ok, entry} =
      if soft_deletable? do
        Brando.Repo.soft_delete(entry)
      else
        Query.delete(entry)
      end

    Content.delete_identifier(module, entry)
    Datasource.update_datasource(module, entry)

    case Brando.Blueprint.Identifier.identifier_for(entry) do
      nil -> nil
      identifier -> Notifications.push_mutation(gettext("deleted"), identifier, user)
    end

    callback_block.(entry)
  end

  defp has_changes(%Ecto.Changeset{changes: changes}) when map_size(changes) > 0, do: true
  defp has_changes(_), do: false
end
