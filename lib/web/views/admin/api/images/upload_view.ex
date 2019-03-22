defmodule Brando.Admin.API.Images.UploadView do
  @moduledoc """
  View for the images upload module.
  """
  use Brando.Web, :view
  use Brando.Sequence, :view

  def render("post.json", %{status: 200, image: image}) do
    # fix image here, so poison doesn't choke
    image =
      image
      |> Map.merge(%{creator: nil, image_series: nil})
      |> prefix_image_urls

    %{status: "200", image: image}
  end

  def render("post.json", params) do
    params
  end

  defp prefix_image_urls(image) do
    sizes = for {k, v} <- image.image.sizes, into: %{}, do: {k, Brando.Utils.media_url(v)}

    put_in(image.image.sizes, sizes)
  end
end
