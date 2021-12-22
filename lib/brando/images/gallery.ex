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
  alias Brando.Images.GalleryImage

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped
  trait Brando.Trait.SoftDelete

  identifier "{{ entry.id }}"

  attributes do
    attribute :config_target, :text
  end

  relations do
    relation :gallery_images, :has_many, module: GalleryImage, preload_order: [asc: :sequence]
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

      actions([
        [label: gettext("Edit image"), event: "edit_entry"],
        [label: gettext("Duplicate image"), event: "duplicate_entry"],
        [
          label: gettext("Delete image"),
          event: "delete_entry",
          confirm: gettext("Are you sure?")
        ]
      ])

      selection_actions([
        [label: gettext("Delete images"), event: "delete_selected"]
      ])
    end
  end

  @derive {Jason.Encoder,
           only: [
             :gallery_images,
             :config_target
           ]}
end
