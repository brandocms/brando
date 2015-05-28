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
    |> assign(:images, InstagramImage.all)
    |> render
  end
end

