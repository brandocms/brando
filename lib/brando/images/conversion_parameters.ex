defmodule Brando.Images.ConversionParameters do
  @moduledoc """
  Store data we need for doing image resizing and cropping
  """

  defstruct id: nil,
            image: nil,
            size_key: nil,
            size_cfg: nil,
            image_src_path: nil,
            image_dest_path: nil,
            image_dest_rel_path: nil,
            original_width: nil,
            original_height: nil,
            resize_width: nil,
            resize_height: nil,
            crop: nil,
            crop_width: nil,
            crop_height: nil,
            focal_point: nil,
            original_focal_point: nil,
            transformed_focal_point: nil,
            anchor: nil,
            quality: "100",
            resize_geography: nil,
            crop_geography: nil

end
