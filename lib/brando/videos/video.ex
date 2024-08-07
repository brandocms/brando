defmodule Brando.Videos.Video do
  @moduledoc """
  Video
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Videos",
    schema: "Video",
    singular: "video",
    plural: "videos",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped
  trait Brando.Trait.SoftDelete

  @cfg [
    formats: [:original, :webp],
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "xlarge",
    upload_path: Path.join(["images", "videos", "covers"]),
    random_filename: true,
    size_limit: 10_240_000,
    sizes: %{
      "micro" => %{"size" => "25", "quality" => 20, "crop" => false},
      "thumb" => %{"size" => "300x300>", "quality" => 70, "crop" => true},
      "small" => %{"size" => "700", "quality" => 70},
      "medium" => %{"size" => "1100", "quality" => 70},
      "large" => %{"size" => "1700", "quality" => 70},
      "xlarge" => %{"size" => "2100", "quality" => 70}
    },
    srcset: %{
      default: [
        {"small", "700w"},
        {"medium", "1100w"},
        {"large", "1700w"},
        {"xlarge", "2100w"}
      ]
    }
  ]

  identifier false
  persist_identifier false

  attributes do
    attribute :url, :text
    attribute :source, :enum, values: [:youtube, :vimeo, :file, :remote_file]
    attribute :filename, :text
    attribute :remote_id, :text
    attribute :width, :integer
    attribute :height, :integer
    attribute :thumbnail_url, :text

    attribute :autoplay, :boolean
    attribute :preload, :boolean
    attribute :loop, :boolean
    attribute :controls, :boolean
    attribute :config_target, :text
  end

  assets do
    asset :cover_image, :image, cfg: @cfg
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
          {% if entry.cover %}
            <img
              width="25"
              height="25"
              src="{{ entry.cover|src:"original" }}" />
          {% else %}
            {% if entry.thumbnail_url %}
              <img
                width="25"
                height="25"
                src="{{ entry.thumbnail_url }}" />
            {% endif %}
          {% endif %}
        </div>
        """,
        columns: 2
      )

      template(
        """
        <small class="monospace">\#{{ entry.id }}</small><br>
        <small class="monospace">
          {% if entry.filename %}
            {{ entry.filename }}
          {% else %}
            {{ entry.url }}
          {% endif %}
        </small><br>
        <small>{{ entry.width }}&times;{{ entry.height }}</small><br>
        {% if entry.title %}<div class="badge mini">#{gettext("Title")}</div>{% endif %}
        {% if entry.alt %}<div class="badge mini">Alt</div>{% endif %}
        """,
        columns: 9
      )
    end
  end
end
