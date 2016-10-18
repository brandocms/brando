defmodule Brando.ImageCategoryForm do
  @moduledoc """
  A form for the ImageCategory schema. See the `Brando.Form` module for more
  documentation
  """

  use Brando.Form
  alias Brando.ImageCategory

  form "imagecategory", [schema: ImageCategory,
                         helper: :admin_image_category_path,
                         class: "grid-form"] do
    field :name, :text
    field :slug, :text, [slug_from: :name]
    submit :save, [class: "btn btn-success"]
  end
end
