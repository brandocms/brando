defmodule Brando.Admin.ImageController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """

  use Brando.Web, :controller

  import Brando.Plug.HTML
  import Brando.Gettext

  alias Brando.Images

  plug :put_section, "images"

  @doc false
  def index(conn, _params) do
    # show images by tabbed category, then series.
    categories = Images.get_categories_with_series_and_images()

    conn
    |> assign(:page_title, gettext("Index - images"))
    |> assign(:categories, categories)
    |> render(:index)
  end

  @doc false
  def delete_selected(conn, %{"ids" => ids}) do
    Images.delete_images(ids)
    render conn, :delete_selected, ids: ids
  end

  @doc false
  def set_properties(conn, %{"id" => id, "form" => form}) do
    image = Images.get_image!(id)

    new_data =
      Enum.reduce form, image.image, fn({attr, val}, acc) ->
        Map.put(acc, String.to_atom(attr), val)
      end

    Images.update_image(image, %{"image" => new_data})

    render conn, :set_properties, id: id, attrs: form
  end
end
