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
    %__MODULE__{
      height: image.height,
      url: hostname(media_url(img_url(image, :xlarge))),
      width: image.width
    }
  end
end
