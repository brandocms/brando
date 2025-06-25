defmodule Brando.Galleries.Gallery do
  @moduledoc """
  Collection of images and videos
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Galleries",
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
    relation :gallery_objects, :has_many,
      module: Brando.Galleries.GalleryObject,
      on_replace: :delete_if_exists,
      preload_order: [asc: :sequence],
      sort_param: :sort_gallery_object_ids,
      drop_param: :drop_gallery_object_ids,
      cast: true
  end

  def preloads_for do
    gallery_objects_query =
      from go in Brando.Galleries.GalleryObject,
        order_by: [asc: go.sequence],
        preload: [:image, :video]

    from g in Brando.Galleries.Gallery,
      preload: [gallery_objects: ^gallery_objects_query]
  end
end
