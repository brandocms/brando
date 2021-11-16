defmodule Brando.Images.Image do
  @moduledoc """
  Embedded image
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Image",
    singular: "image",
    plural: "images",
    gettext_module: Brando.Gettext

  alias Brando.Images.Focal
  import Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Sequenced
  trait Brando.Trait.SoftDelete

  identifier "{{ entry.id }}"

  attributes do
    attribute :status, Ecto.Enum, values: [:processed, :unprocessed]
    attribute :title, :text
    attribute :credits, :text
    attribute :alt, :text
    attribute :formats, {:array, Ecto.Enum}, values: [:original, :jpg, :png, :gif, :webp, :avif]
    attribute :path, :text, required: true
    attribute :width, :integer
    attribute :height, :integer
    attribute :sizes, :map
    attribute :cdn, :boolean, default: false
    attribute :dominant_color, :text
    attribute :config_target, :text
  end

  relations do
    relation :focal, :embeds_one, module: Focal
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
             :title,
             :credits,
             :formats,
             :alt,
             :focal,
             :path,
             :sizes,
             :width,
             :height,
             :cdn,
             :dominant_color,
             :config_target
           ]}
end
