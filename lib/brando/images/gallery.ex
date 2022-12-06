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

  identifier "{{ entry.id }}"

  attributes do
    attribute :config_target, :text
  end

  assets do
    asset :gallery_images, :gallery_images
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

  @derive {Jason.Encoder,
           only: [
             :gallery_images,
             :config_target
           ]}
end
