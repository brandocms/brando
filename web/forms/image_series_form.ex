defmodule Brando.ImageSeriesForm do
  @moduledoc """
  A form for the ImageCategory model. See the `Brando.Form` module for more
  documentation
  """
  use Brando.Form
  alias Brando.ImageCategory

  @doc false
  def get_categories(_) do
    cats = ImageCategory |> ImageCategory.with_image_series_and_images |> Brando.repo.all
    for cat <- cats, do: [value: cat.id, text: cat.name]
  end

  form "imageseries", [model: Brando.ImageSeries, helper: :admin_image_series_path, class: "grid-form"] do
    fieldset do
      field :image_category_id, :radio, [required: true, choices: &__MODULE__.get_categories/1]
    end
    field :name, :text, [required: true]
    field :slug, :text, [required: true, slug_from: :name]
    field :credits, :text, [required: false]
    submit :save, [class: "btn btn-success"]
  end
end