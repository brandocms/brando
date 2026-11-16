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
  @sitemap_header "x-brando-ssg-sitemap"

  @spec header() :: String.t()
  def header, do: @header

  @doc """
  The header a build sends with its `robots.txt` request: `1` when the build
  has a sitemap for robots.txt to name, `0` when it has none. Only a request
  with a valid signed context (`Brando.Plug.Tenant` marks it
  `conn.private.brando_ssg_build`) is answered by it.
  """
  @spec sitemap_header() :: String.t()
  def sitemap_header, do: @sitemap_header

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
