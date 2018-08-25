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
      |> add_image_urls

    %{status: "200", image: image}
  end

  def render("post.json", params) do
    params
  end

  defp add_image_urls(image) do
    image =
      put_in(
        image.image,
        Map.put(
          image.image,
          :thumb,
          Brando.Utils.img_url(image.image, :thumb, prefix: Brando.Utils.media_url())
        )
      )

    put_in(
      image.image,
      Map.put(
        image.image,
        :medium,
        Brando.Utils.img_url(image.image, :medium, prefix: Brando.Utils.media_url())
      )
    )
  end
end
