defmodule Brando.Admin.InstagramController do
  @moduledoc """
  Controller for the Instagram module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  import Brando.Plug.Section
  import Ecto.Query
  alias Brando.InstagramImage

  plug :put_section, "instagram"

  @doc """
  Renders the main index.
  """
  def index(conn, _params) do
    language = Brando.I18n.get_language(conn)
    images =
      InstagramImage
      |> select([m], %{id: m.id, status: m.status, image: m.image, created_time: m.created_time})
      |> order_by([m], [desc: m.status, desc: m.created_time])
      |> Brando.repo.all
    conn
    |> assign(:page_title, t!(language, "title.index"))
    |> assign(:images, images)
    |> render
  end

  def change_status(conn, %{"ids" => ids, "status" => status}) do
    InstagramImage.change_status_for(ids, status)
    conn
    |> json(%{status: "200", ids: ids, new_status: status})
  end

  locale "en", [
    title: [
      index: "Index – Instagram",
    ]
  ]

  locale "no", [
    title: [
      index: "Index – Instagram",
    ]
  ]
end

