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
  trait Brando.Trait.SoftDelete
  trait Brando.Trait.Focal

  identifier false
  persist_identifier false

  attributes do
    attribute :status, Ecto.Enum, values: [:processed, :unprocessed]
    attribute :title, :text
    attribute :credits, :text
    attribute :alt, :text

    attribute :formats, {:array, Ecto.Enum},
      values: [:original, :jpg, :png, :gif, :webp, :avif, :svg]

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
        [label: t("Path"), filter: "path"]
      ])

      template(
        """
        <div class="padded">
          <img
            width="25"
            height="25"
            src="{{ entry|src:"smallest" }}" />
        </div>
        """,
        columns: 2
      )

      template(
        """
        <small class="monospace">\#{{ entry.id }}</small><br>
        <small class="monospace">{{ entry.path }}</small><br>
        <small>{{ entry.width }}&times;{{ entry.height }}</small><br>
        {% if entry.title %}<div class="badge mini">#{gettext("Title")}</div>{% endif %}
        {% if entry.alt %}<div class="badge mini">Alt</div>{% endif %}
        """,
        columns: 9
      )
    end
  end

  forms do
    form do
      tab gettext("Content") do
        fieldset size: :half do
          input :title, :text, label: t("Title")
          input :credits, :text, label: t("Credits")
          input :alt, :text, label: t("Alt. text")
          input :path, :text, label: t("Path"), monospace: true
        end

        fieldset size: :half do
          input :cdn, :toggle,
            label: t("CDN"),
            instructions: t("Asset has been transferred to CDN")

          input :width, :number, label: t("Width"), monospace: true
          input :height, :number, label: t("Height"), monospace: true
          input :dominant_color, :color, label: t("Dominant color"), monospace: true
          input :config_target, :text, label: t("Configuration target"), monospace: true
        end
      end
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
