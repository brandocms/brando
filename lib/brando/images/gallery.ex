defmodule Brando.Images.Gallery do
  @moduledoc """
  Collection of images
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Gallery",
    singular: "gallery",
    plural: "galleries",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext
  import Ecto.Query

  trait Brando.Trait.Timestamped
  trait Brando.Trait.SoftDelete

  identifier false
  persist_identifier false

  attributes do
    attribute :config_target, :text
  end

  relations do
    relation :gallery_images, :has_many,
      module: Brando.Images.GalleryImage,
      on_replace: :delete_if_exists,
      preload_order: [asc: :sequence],
      sort_param: :sort_gallery_image_ids,
      drop_param: :drop_gallery_image_ids,
      cast: true
  end

  def preloads_for do
    gallery_images_query =
      from gi in Brando.Images.GalleryImage,
        order_by: [asc: gi.sequence],
        preload: [:image]

    from g in Brando.Images.Gallery,
      preload: [gallery_images: ^gallery_images_query]
  end
end
