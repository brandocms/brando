defmodule Brando.Admin.InstagramController do
  @moduledoc """
  Controller for the Instagram module.
  """

  use Brando.Web, :controller
  import Brando.Plug.Section
  alias Brando.InstagramImage

  plug :put_section, "instagram"
  plug :action

  @doc """
  Renders the main index.
  """
  def index(conn, _params) do
    conn
    |> assign(:images, InstagramImage.all_grouped)
    |> render
  end

  def change_status(conn, %{"ids" => ids, "status" => status}) do
    InstagramImage.change_status_for(ids, status)
    conn
    |> json(%{status: "200", ids: ids, new_status: status})
  end
end

