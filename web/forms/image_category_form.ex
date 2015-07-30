defmodule Brando.ImageCategoryForm do
  @moduledoc """
  A form for the ImageCategory model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form

  form "imagecategory", [model: Brando.ImageCategory, helper: :admin_image_category_path, class: "grid-form"] do
    field :name, :text, [required: true]
    field :slug, :text, [required: true, slug_from: :name]
    submit :save, [class: "btn btn-success"]
  end
end