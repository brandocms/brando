defmodule Brando.Images.ImageSeriesForm do
  @moduledoc """
  A form for the ImageCategory model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form
  alias Brando.Images.Model.ImageCategory

  def get_categories do
    for cat <- ImageCategory.all, do: [value: cat.id, text: cat.name]
  end

  form "imageseries", [helper: :admin_image_series_path, class: "grid-form"] do
    field :image_category_id, :select,
      [required: true,
       label: "Kategori",
       choices: &__MODULE__.get_categories/0]
    field :name, :text,
      [required: true,
       label: "Navn",
       placeholder: "Navn"]
    field :slug, :text,
      [required: true,
       label: "URL-slug",
       placeholder: "URL-slug"]
    field :credits, :text,
      [required: false,
       label: "Kreditering",
       placeholder: "Kreditering"]
    submit "Lagre",
      [class: "btn btn-default"]
  end
end