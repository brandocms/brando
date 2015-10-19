defmodule Brando.Admin.ImageController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """
  use Linguist.Vocabulary
  use Brando.Web, :controller
  import Brando.Plug.HTML
  import Brando.Gettext
  alias Brando.Image

  plug :put_section, "images"

  @doc false
  def index(conn, _params) do
    # show images by tabbed category, then series.
    category_model = conn.private[:category_model]
    categories =
      category_model
      |> category_model.with_image_series_and_images
      |> Brando.repo.all

    conn
    |> assign(:page_title, gettext("Index - images"))
    |> assign(:categories, categories)
    |> render(:index)
  end

  @doc false
  def delete_selected(conn, %{"ids" => ids}) do
    model = conn.private[:image_model]
    model.delete(ids)
    render(conn, :delete_selected, ids: ids)
  end

  @doc false
  def set_properties(conn, %{"id" => id, "form" => form}) do
    image = Image |> Brando.repo.get!(id)
    image_data = image.image

    new_data =
      Enum.reduce form, image_data, fn({attr, val}, acc) ->
        Map.put(acc, String.to_atom(attr), val)
      end

    Brando.repo.update!(Map.put(image, :image, new_data))

    render(conn, :set_properties, id: id, attrs: form)
  end
end
