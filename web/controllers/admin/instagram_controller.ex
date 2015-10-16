defmodule Brando.Admin.InstagramController do
  @moduledoc """
  Controller for the Instagram module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  import Brando.Gettext
  import Brando.Plug.HTML
  import Ecto.Query
  alias Brando.InstagramImage

  plug :put_section, "instagram"

  @doc """
  Renders the main index.
  """
  def index(conn, _params) do
    images = Brando.repo.all(
      from i in InstagramImage,
        select: %{id: i.id, status: i.status, image: i.image,
                  created_time: i.created_time},
        order_by: [desc: i.status, desc: i.created_time]
    )

    conn
    |> assign(:page_title, gettext("Index - Instagram"))
    |> assign(:images, images)
    |> render
  end

  def change_status(conn, %{"ids" => ids, "status" => status}) do
    InstagramImage.change_status_for(ids, status)
    json(conn, %{status: "200", ids: ids, new_status: status})
  end
end
