defmodule E2eProjectWeb.ProjectController do
  use BrandoWeb, :controller
  alias E2eProject.Projects
  alias E2eProjectWeb.FallbackController

  @type conn :: Plug.Conn.t()

  action_fallback FallbackController

  @doc false
  @spec list(conn, map) :: conn
  def list(conn, _params) do
    list_opts = %{}

    with {:ok, projects} <- Projects.list_projects(list_opts) do
      conn
      |> assign(:projects, projects)
      |> put_section("projects")
      |> render(:list)
    end
  end

  @doc false
  @spec detail(conn, map) :: {:error, {:project, :not_found}} | conn
  def detail(conn, %{"slug" => slug}) do
    opts = %{matches: %{slug: slug}, preload: [:alternate_entries], status: :published}

    with {:ok, project} <- Projects.get_project(opts) do
      conn
      |> assign(:entry, project)
      |> put_hreflang(project)
      |> put_section("project")
      |> render(:detail)
    end
  end
end
