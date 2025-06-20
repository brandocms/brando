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

  use Gettext, backend: Brando.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped
  trait Brando.Trait.SoftDelete

  @thumbnail_cfg %{
    formats: [:original, :webp],
    allowed_mimetypes: ["image/jpeg", "image/png", "image/gif"],
    default_size: "xlarge",
    upload_path: Path.join(["images", "videos", "thumbnails"]),
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
  }

  identifier false
  persist_identifier false

  attributes do
    attribute :type, :enum, values: [:upload, :external_file, :vimeo, :youtube]
    attribute :title, :text
    attribute :caption, :text
    attribute :aspect_ratio, :string
    attribute :width, :integer
    attribute :height, :integer
    attribute :autoplay, :boolean
    attribute :preload, :boolean
    attribute :loop, :boolean
    attribute :controls, :boolean
    attribute :source_url, :text
    attribute :remote_id, :text
    attribute :config_target, :text
  end

  assets do
    asset :file, :file, cfg: :config_target
    asset :thumbnail, :image, cfg: @thumbnail_cfg
  end

  listings do
    listing do
      query %{order: [{:desc, :id}]}
      filter label: t("Path"), filter: "path"
      component &__MODULE__.listing_row/1
    end
  end

  forms do
    form do
      tab gettext("Content") do
        fieldset do
          size :half
          input :title, :text, label: t("Title")
          input :caption, :text, label: t("Caption")
          input :type, :select, label: t("Type"),
            options: [
              %{label: "Upload", value: :upload},
              %{label: "External file", value: :external_file},
              %{label: "Vimeo", value: :vimeo},
              %{label: "YouTube", value: :youtube}
            ]
          input :source_url, :text, label: t("Source URL"), monospace: true
          input :remote_id, :text, label: t("Remote ID"), monospace: true
          input :width, :number, label: t("Width"), monospace: true
          input :height, :number, label: t("Height"), monospace: true
          input :aspect_ratio, :text, label: t("Aspect ratio"), monospace: true
          input :config_target, :text, label: t("Configuration target"), monospace: true
        end

        fieldset do
          size :half
          input :autoplay, :toggle, label: t("Autoplay")
          input :preload, :toggle, label: t("Preload")
          input :loop, :toggle, label: t("Loop")
          input :controls, :toggle, label: t("Controls")
          input :file, :file, label: t("Video file")
          input :thumbnail, :image, label: t("Thumbnail")
        end
      end
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.field columns={1}>
      <div class="padded">
        <img :if={@entry.thumbnail} width="25" height="25" src={Brando.Utils.img_url(@entry.thumbnail, :smallest)} />
      </div>
    </.field>
    <.field columns={1}>
      <small class="monospace">#{@entry.id}</small>
    </.field>
    <.update_link entry={@entry} columns={8}>
      {@entry.title || gettext("Untitled")}
      <:outside>
        <br />
        <div>
          <small>
            <%= case @entry.type do %>
              <% :upload -> %>
                Upload: {@entry.file.filename}

              <% :external_file -> %>
                External file <span :if={@entry.source_url}>({URI.parse(@entry.source_url).host})</span>

              <% _ -> %>
                {@entry.type}: {@entry.source_url || @entry.remote_id}
            <% end %>
          </small>
        </div>
        <div><small>{@entry.width}&times;{@entry.height}</small></div>
      </:outside>
    </.update_link>
    <.url entry={@entry} />
    """
  end
end
