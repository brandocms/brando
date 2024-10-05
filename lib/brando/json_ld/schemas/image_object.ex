defmodule Brando.JSONLD.Schema.ImageObject do
  @moduledoc """
  ImageObject schema
  """

  import Brando.Utils, only: [media_url: 1, img_url: 2, hostname: 1]

  @derive Jason.Encoder
  defstruct "@type": "ImageObject",
            height: nil,
            url: nil,
            width: nil

  def build(nil) do
    nil
  end

  def build(image) do
    largest_size_url =
      image
      |> img_url(:largest)
      |> media_url()
      |> hostname()

    %__MODULE__{
      url: largest_size_url,
      height: image.height,
      width: image.width
    }
  end
end
