defmodule Brando.Authorization.Operations do
  @moduledoc "Capability checks for site lifecycle operations outside generated contexts."
  alias Brando.Authorization.{Boundary, Engine, Scope}

  def run(action, resource, site_id, opts, fun) do
    actor = opts[:creator] || opts[:actor] || Boundary.current_scope() || actor_id(opts[:creator_id])
    with :ok <- authorize(actor, action, resource, site_id), do: fun.()
  end

  def authorize(:system, _, _, _), do: :ok

  def authorize(actor, action, resource, site_id) do
    if Engine.enabled?() do
      scope = Boundary.actor_scope(actor)

      with false <- scope.kind == :site and scope.site_id != site_id,
           %{id: ^site_id} = site <- Brando.Repo.get(Brando.Sites.Site, site_id) do
        Engine.authorize(Scope.site(%{id: scope.user_id}, site), action, resource)
      else
        _ -> {:error, :forbidden}
      end
    else
      :ok
    end
  end

  defp actor_id(nil), do: nil
  defp actor_id(id), do: %{id: id}
end
