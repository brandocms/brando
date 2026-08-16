defmodule Brando.SSG.Context do
  @moduledoc """
  Signs short-lived tenant context used by the SSG HTTP renderer.

  A build may render any named environment, including one without a public
  domain. The signed header lets `Brando.Plug.Tenant` select that environment
  without changing DNS or temporarily mutating the tenant registry.
  """

  alias Brando.Environments.Environment
  alias Brando.Sites.Site
  alias Brando.Tenant.Registry

  @salt "brando-ssg-context"
  @max_age 3_600
  @header "x-brando-ssg-token"

  @spec header() :: String.t()
  def header, do: @header

  @spec sign(Site.t(), Environment.t()) :: String.t()
  def sign(%Site{id: site_id}, %Environment{id: environment_id, site_id: site_id}) do
    Phoenix.Token.sign(Brando.endpoint(), @salt, %{site_id: site_id, environment_id: environment_id})
  end

  @spec resolve(String.t()) :: {Site.t(), Environment.t()} | nil
  def resolve(token) when is_binary(token) do
    with {:ok, %{site_id: site_id, environment_id: environment_id}} <-
           Phoenix.Token.verify(Brando.endpoint(), @salt, token, max_age: @max_age),
         %Site{status: :active} = site <- Registry.get_site(site_id),
         %Environment{site_id: ^site_id} = environment <- Registry.get_environment(environment_id) do
      {site, environment}
    else
      _invalid_or_expired -> nil
    end
  end

  def resolve(_token), do: nil
end
