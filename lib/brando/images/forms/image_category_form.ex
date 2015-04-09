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
       placeholder: "URL-slug",
       slug_from: :name]
    submit "Lagre",
      [class: "btn btn-success"]
  end
end