defmodule Brando.Admin.ImageController do
  @moduledoc """
  Controller for the Brando ImageCategory module.
  """

  use Brando.Web, :controller

  alias Brando.Image
  alias Brando.ImageCategory

  import Brando.Plug.HTML
  import Brando.Gettext

  plug :put_section, "images"

  @doc false
  def index(conn, _params) do
    # show images by tabbed category, then series.
    categories = ImageCategory
                 |> ImageCategory.with_image_series_and_images
                 |> Brando.repo.all

    conn
    |> assign(:page_title, gettext("Index - images"))
    |> assign(:categories, categories)
    |> render(:index)
  end

  @doc false
  def delete_selected(conn, %{"ids" => ids}) do
    Image.delete(ids)
    render conn, :delete_selected, ids: ids
  end

  @doc false
  def set_properties(conn, %{"id" => id, "form" => form}) do
    image = Brando.repo.get!(Image, id)

    new_data =
      Enum.reduce form, image.image, fn({attr, val}, acc) ->
        Map.put(acc, String.to_atom(attr), val)
      end

    image
    |> Image.changeset(:update, %{"image" => new_data})
    |> Brando.repo.update!

    render conn, :set_properties, id: id, attrs: form
  end
end
