defmodule Brando.Authorization.Scope do
  @moduledoc """
  The authenticated actor and the site/environment in which an action takes place.

  Construct scopes on the server, using the authenticated user and resolved site.
  IDs and prefixes submitted by a browser are not authorization scopes. The
  evaluator reloads account and site eligibility before protected operations.
  """

  defstruct [:user_id, :site_id, :environment_id, :prefix, kind: :standalone]

  @type t :: %__MODULE__{
          user_id: integer() | nil,
          site_id: integer() | nil,
          environment_id: integer() | nil,
          prefix: String.t() | nil,
          kind: :standalone | :site | :installation
        }

  @doc "A scope for an installation-wide operation, such as managing global accounts."
  def installation(user), do: %__MODULE__{user_id: user_id(user), kind: :installation}

  @doc "A scope for a standalone installation without tenancy."
  def standalone(user), do: %__MODULE__{user_id: user_id(user), kind: :standalone}

  @doc "A scope within a resolved site, optionally within one of its environments."
  def site(user, site, environment \\ nil) do
    %__MODULE__{
      user_id: user_id(user),
      kind: :site,
      site_id: site.id,
      environment_id: environment && environment.id,
      prefix: environment && Brando.Tenant.prefix(site, environment)
    }
  end

  @doc "Builds a scope from the server's current tenant context."
  def current(%__MODULE__{} = scope), do: scope

  def current(user) do
    if Brando.Tenant.enabled?() do
      resolve_prefix(user, Brando.Tenant.current_prefix())
    else
      standalone(user)
    end
  end

  defp resolve_prefix(user, "tenant_" <> suffix) do
    with [site_key, environment_key] <- String.split(suffix, "_", parts: 2),
         site when not is_nil(site) <- Brando.Tenant.Registry.get_site_by_key(site_key),
         environment when not is_nil(environment) <-
           Brando.Repo.get_by(Brando.Environments.Environment, site_id: site.id, key: environment_key) do
      site(user, site, environment)
    else
      _ -> installation(user)
    end
  end

  defp resolve_prefix(user, _), do: installation(user)
  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end
