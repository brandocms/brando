defmodule Brando.Admin.InstagramController do
  @moduledoc """
  Controller for the Instagram module.
  """

  use Brando.Web, :controller
  import Brando.Plug.Section
  import Ecto.Query
  alias Brando.InstagramImage

  plug :put_section, "instagram"
  plug :action

  @doc """
  Renders the main index.
  """
  def index(conn, _params) do
    images =
      InstagramImage
      |> order_by([m], [desc: m.status, asc: m.instagram_id])
      |> Brando.repo.all
    conn
    |> assign(:images, images)
    |> render
  end

  def change_status(conn, %{"ids" => ids, "status" => status}) do
    InstagramImage.change_status_for(ids, status)
    conn
    |> json(%{status: "200", ids: ids, new_status: status})
  end
end

