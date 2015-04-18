defmodule Brando.ImageCategoryConfigForm do
  @moduledoc """
  A form for the ImageCategory configuration model. See the `Brando.Form`
  module for more documentation
  """
  use Brando.Form

  form "imagecategoryconfig", [helper: :admin_image_category_path, class: "grid-form"] do
    field :cfg, :textarea,
      [required: true,
       label: "Konfigurasjon",
       placeholder: "Konfigurasjon"]
    submit "Lagre",
      [class: "btn btn-success"]
  end
end