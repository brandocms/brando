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

  import Brando.Gettext

  trait Brando.Trait.Timestamped
  trait Brando.Trait.SoftDelete

  identifier false

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

  listings do
    listing do
      listing_query %{
        order: [{:desc, :id}]
      }

      filters([
        [label: gettext("Path"), filter: "path"]
      ])

      template(
        """
        <div class="padded">
          <img
            width="25"
            height="25"
            src="{{ entry|src:"original" }}" />
        </div>
        """,
        columns: 2
      )

      template(
        """
        <small class="monospace">\#{{ entry.id }}</small><br>
        <small class="monospace">{{ entry.path }}</small><br>
        <small>{{ entry.width }}&times;{{ entry.height }}</small>
        """,
        columns: 8
      )
    end
  end
end
