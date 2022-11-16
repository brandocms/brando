defmodule Brando.Query.Mutations do
  import Brando.Gettext

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
    changeset_fun = custom_changeset || (&module.changeset/4)

    changeset =
      struct(module)
      |> changeset_fun.(params, user, opts)
      |> Publisher.maybe_override_status()

    case Query.insert(changeset) do
      {:ok, entry} ->
        {:ok, entry} = maybe_preload(entry, preloads)
        {:ok, _} = Datasource.update_datasource(module, entry)
        {:ok, _} = Publisher.schedule_publishing(entry, changeset, user)

        revisioned? = module.__trait__(Trait.Revisioned)

        if revisioned? do
          Revisions.create_revision(entry, user)
        end

        case Brando.Blueprint.Identifier.identifier_for(entry) do
          nil -> nil
          identifier -> Notifications.push_mutation(gettext("created"), identifier, user)
        end

        callback_block.(entry)

      err ->
        err
    end
  end

  def create_with_changeset(module, changeset, user, callback_block, opts) do
    {preloads, _opts} = Keyword.pop(opts, :preloads)

    with changeset <- Publisher.maybe_override_status(changeset),
         changeset <- set_action(changeset, :insert),
         {:ok, entry} <- Query.insert(changeset),
         {:ok, entry} <- maybe_preload(entry, preloads),
         {:ok, _} <- Datasource.update_datasource(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      revisioned? = module.__trait__(Trait.Revisioned)

      if revisioned? do
        Revisions.create_revision(entry, user)
      end

      case Brando.Blueprint.Identifier.identifier_for(entry) do
        nil -> nil
        identifier -> Notifications.push_mutation(gettext("created"), identifier, user)
      end

      callback_block.(entry)
    end
  end

  defp maybe_preload(entry, nil), do: {:ok, entry}
  defp maybe_preload(entry, preloads), do: {:ok, entry |> Brando.repo().preload(preloads)}

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
    changeset_fun = custom_changeset || (&module.changeset/3)

    get_opts =
      if preloads do
        %{matches: %{id: id}, preload: preloads}
      else
        %{matches: %{id: id}}
      end

    with {:ok, entry} <- apply(context, :"get_#{name}", [get_opts]),
         changeset <- changeset_fun.(entry, params, user),
         changeset <- Publisher.maybe_override_status(changeset),
         changeset <- set_action(changeset, :update),
         {:ok, entry} <- Query.update(changeset),
         {:ok, _} <- Datasource.update_datasource(module, entry),
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

  def update_with_changeset(module, changeset, user, preloads, callback_block) do
    with changeset <- Publisher.maybe_override_status(changeset),
         changeset <- set_action(changeset, :update),
         {:ok, entry} <- Query.update(changeset),
         {:ok, entry} <- maybe_preload(entry, preloads),
         {:ok, _} <- Datasource.update_datasource(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      if has_changes(changeset) do
        revisioned? = module.__trait__(Trait.Revisioned)

        if revisioned? do
          Revisions.create_revision(entry, user)
        end

        case Brando.Blueprint.Identifier.identifier_for(entry) do
          nil -> nil
          identifier -> Notifications.push_mutation(gettext("updated"), identifier, user)
        end

        callback_block.(entry)
      else
        {:ok, entry}
      end
    else
      err -> err
    end
  end

  def duplicate(context, _module, name, id, opts, override_opts, user) do
    case apply(context, :"get_#{name}", [id]) do
      {:ok, entry} ->
        override_opts = Enum.into(override_opts, %{})

        opts =
          opts
          |> Enum.into(%{})
          |> Map.merge(override_opts)

        params =
          entry
          |> maybe_change_fields(opts)
          |> maybe_delete_fields(opts)
          |> maybe_set_status()
          |> Utils.map_from_struct()
          |> maybe_merge_fields(opts)
          |> drop_id()

        apply(context, :"create_#{name}", [params, user, [skip_villain: true]])

      err ->
        err
    end
  end

  defp drop_id(%{id: _} = entry), do: Map.drop(entry, [:id])
  defp drop_id(entry), do: entry

  defp maybe_set_status(%{status: _} = entry), do: Map.put(entry, :status, :draft)
  defp maybe_set_status(entry), do: entry

  defp maybe_change_fields(entry, %{change_fields: change_fields}) do
    Enum.reduce(change_fields, entry, fn
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
        Brando.repo().soft_delete(entry)
      else
        Query.delete(entry)
      end

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
