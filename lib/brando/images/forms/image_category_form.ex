defmodule Brando.Images.ImageCategoryForm do
  @moduledoc """
  A form for the ImageCategory model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  form "imagecategory", [helper: :admin_image_category_path, class: "grid-form"] do
    field :name, :text,
      [required: true,
       label: "Navn",
       placeholder: "Navn"]
    field :slug, :text,
      [required: true,
       label: "URL-slug",
       placeholder: "URL-slug"]
    field :cfg, :textarea,
      [label: "Konfigurasjon"]
    submit "Lagre",
      [class: "btn btn-default"]
  end
end