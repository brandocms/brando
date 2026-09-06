defmodule Brando.Authorization.Preview do
  @moduledoc "Authority for private, unsaved live previews. Shared previews use their separate publication flow."
  alias Brando.Authorization.{Boundary, Engine, Scope}
  alias Brando.Repo

  @ttl :timer.hours(1)

  def register(key, changeset) do
    if Engine.enabled?() do
      scope = Boundary.current_scope()
      entry = Ecto.Changeset.apply_changes(changeset)

      if editable?(scope, entry) do
        Cachex.put(:cache, cache_key(key), %{scope: scope, entry: entry}, expire: @ttl)
        :ok
      else
        {:error, :forbidden}
      end
    else
      :ok
    end
  end

  def authorize(key, user_id) do
    if Engine.enabled?() do
      with {:ok, %{scope: %Scope{user_id: ^user_id} = scope, entry: entry}} <- metadata(key),
           true <- editable?(scope, entry) do
        :ok
      else
        _ -> {:error, :forbidden}
      end
    else
      Brando.Authorization.Realtime.authorize_account(user_id)
    end
  end

  def authorize_write(key, changeset) do
    if Engine.enabled?() do
      with %Scope{} = scope <- Boundary.current_scope(),
           {:ok, %{scope: ^scope, entry: original}} <- metadata(key),
           entry <- Ecto.Changeset.apply_changes(changeset),
           true <- original.__struct__ == entry.__struct__ and original.id == entry.id,
           true <- editable?(scope, entry) do
        :ok
      else
        _ -> {:error, :forbidden}
      end
    else
      :ok
    end
  end

  def authorize_broadcast(key) do
    if Engine.enabled?() do
      with %Scope{user_id: id} = scope <- Boundary.current_scope(),
           {:ok, %{scope: ^scope}} <- metadata(key) do
        authorize(key, id)
      else
        _ -> {:error, :forbidden}
      end
    else
      :ok
    end
  end

  def authorize_share(user, changeset) do
    if Engine.enabled?() do
      scope = Boundary.actor_scope(user)
      entry = Ecto.Changeset.apply_changes(changeset)

      with true <- editable?(scope, entry),
           :ok <- Engine.authorize(scope, :export, entry),
           true <- is_nil(entry.id) or not is_nil(Repo.get(Engine.scope(scope, :export, entry.__struct__), entry.id)) do
        :ok
      else
        _ -> {:error, :forbidden}
      end
    else
      :ok
    end
  end

  def cleanup(key), do: Cachex.del(:cache, cache_key(key))

  defp metadata(key) when is_binary(key), do: Cachex.get(:cache, cache_key(key))
  defp metadata(_), do: {:error, :forbidden}
  defp cache_key(key), do: "__live_preview_authority__#{key}"

  defp editable?(%Scope{} = scope, %{id: nil} = entry), do: Engine.can?(scope, :create, entry)

  defp editable?(%Scope{} = scope, %{id: id, __struct__: schema} = entry) do
    with true <- Engine.can?(scope, :update, entry),
         fresh when not is_nil(fresh) <- scope |> Engine.scope(:read, schema) |> Repo.get(id),
         true <- is_nil(Map.get(fresh, :deleted_at)) do
      Engine.can?(scope, :update, fresh)
    else
      _ -> false
    end
  end

  defp editable?(_, _), do: false
end
