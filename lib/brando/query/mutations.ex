defmodule Brando.Query.Mutations do
  import Brando.Gettext

  alias Brando.Datasource
  alias Brando.Images
  alias Brando.Notifications
  alias Brando.Publisher
  alias Brando.Query
  alias Brando.Revisions
  alias Brando.Schema
  alias Brando.SoftDelete

  def create(module, params, user, callback_block) do
    with changeset <- module.changeset(struct(module), params, user),
         changeset <- Publisher.maybe_override_status(changeset),
         {:ok, entry} <- Query.insert(changeset),
         {:ok, _} <- Datasource.update_datasource(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      if Revisions.is_revisioned(module) do
        Revisions.create_revision(entry, user)
      end

      case Schema.identifier_for(entry) do
        nil -> nil
        identifier -> Notifications.push_mutation(gettext("created"), identifier, user)
      end

      callback_block.(entry)
    else
      err -> err
    end
  end

  def update(context, module, name, id, params, user, preloads, callback_block) do
    get_opts =
      if preloads do
        %{matches: %{id: id}, preload: preloads}
      else
        %{matches: %{id: id}}
      end

    with {:ok, entry} <- apply(context, :"get_#{name}", [get_opts]),
         changeset <- module.changeset(entry, params, user),
         changeset <- Publisher.maybe_override_status(changeset),
         {:ok, entry} <- Query.update(changeset),
         {:ok, _} <- Datasource.update_datasource(module, entry),
         {:ok, _} <- Publisher.schedule_publishing(entry, changeset, user) do
      if has_changes(changeset) do
        if Revisions.is_revisioned(module) do
          Revisions.create_revision(entry, user)
        end

        case Schema.identifier_for(entry) do
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

  def duplicate(context, _module, name, id, opts, user) do
    case apply(context, :"get_#{name}", [id]) do
      {:ok, entry} ->
        opts = Enum.into(opts, %{})

        params =
          entry
          |> maybe_change_fields(opts)
          |> maybe_delete_fields(opts)
          |> maybe_set_status()
          |> Map.from_struct()
          |> drop_id()

        apply(context, :"create_#{name}", [params, user])

      err ->
        err
    end
  end

  defp drop_id(%{id: _} = entry), do: Map.drop(entry, [:id])
  defp drop_id(entry), do: entry

  defp maybe_set_status(%{status: _} = entry), do: Map.put(entry, :status, :draft)
  defp maybe_set_status(entry), do: entry

  defp maybe_change_fields(entry, %{change_fields: change_fields}) do
    Enum.reduce(change_fields, entry, fn f, updated_entry ->
      default_value = Map.get(updated_entry, f)
      Map.update(updated_entry, f, default_value, fn v -> "#{v}_dupl" end)
    end)
  end

  defp maybe_change_fields(entry, _), do: entry

  defp maybe_delete_fields(entry, %{delete_fields: delete_fields}) do
    Map.delete(entry, delete_fields)
  end

  defp maybe_delete_fields(entry, _), do: entry

  def delete(context, module, name, id, user, callback_block) do
    {:ok, entry} = apply(context, :"get_#{name}", [id])

    {:ok, entry} =
      if SoftDelete.is_soft_deletable(module) do
        Brando.repo().soft_delete(entry)
      else
        Query.delete(entry)
      end

    if {:__gallery_fields__, 0} in module.__info__(:functions) do
      for f <- apply(module, :__gallery_fields__, []) do
        image_series_id = String.to_existing_atom("#{to_string(f)}_id")
        Images.delete_series(Map.get(entry, image_series_id))
      end
    end

    Datasource.update_datasource(module, entry)

    case Schema.identifier_for(entry) do
      nil -> nil
      identifier -> Notifications.push_mutation(gettext("deleted"), identifier, user)
    end

    callback_block.(entry)
  end

  defp has_changes(%Ecto.Changeset{changes: changes}) when map_size(changes) > 0, do: true
  defp has_changes(_), do: false
end
