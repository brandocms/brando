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
  has a sitemap for robots.txt to name, `0` when it has none. Only a build's
  request (`build_request?/1`) is answered by it.
  """
  @spec sitemap_header() :: String.t()
  def sitemap_header, do: @sitemap_header

  @doc """
  Whether `conn` is a static build's request: marked
  `conn.private.brando_ssg_build` by `Brando.Plug.Tenant`, which marks one
  whose signed context resolves (`resolve/1`). With `tenancy_mode: :none`,
  which has no site to resolve, a request that carries a valid signed context
  is one too, whether that plug ran or not. A request without one never is.
  """
  @spec build_request?(Plug.Conn.t()) :: boolean()
  def build_request?(%Plug.Conn{private: %{brando_ssg_build: true}}), do: true
  def build_request?(%Plug.Conn{} = conn), do: not Brando.Tenant.enabled?() and signed?(conn)

  defp signed?(conn) do
    case Plug.Conn.get_req_header(conn, @header) do
      [token | _] -> match?({:ok, %{site_id: _, environment_id: _}}, verify(token))
      [] -> false
    end
  end

  @doc """
  Signs a build's context: the site and environment it builds, or with
  `tenancy_mode: :none` the standalone site (`Brando.SSG.build/1`), whose ids
  are nil.
  """
  @spec sign(Site.t(), Environment.t()) :: String.t()
  def sign(%Site{id: site_id}, %Environment{id: environment_id, site_id: site_id}) do
    Phoenix.Token.sign(Brando.endpoint(), @salt, %{site_id: site_id, environment_id: environment_id})
  end

  @spec resolve(String.t()) :: {Site.t(), Environment.t()} | nil
  def resolve(token) when is_binary(token) do
    # A standalone build's context (`tenancy_mode: :none`) names no site
    with {:ok, %{site_id: site_id, environment_id: environment_id}}
         when not is_nil(site_id) and not is_nil(environment_id) <- verify(token),
         %Site{status: :active} = site <- Registry.get_site(site_id),
         %Environment{site_id: ^site_id} = environment <- Registry.get_environment(environment_id) do
      {site, environment}
    else
      _invalid_or_expired -> nil
    end
  end

  def resolve(_token), do: nil

  defp verify(token), do: Phoenix.Token.verify(Brando.endpoint(), @salt, token, max_age: @max_age)
end
