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

  @thumbnail_cfg [
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
  ]

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

  def listing_row(assigns) do
    ~H"""
    <.field columns={2}>
      <div class="padded">
        <img :if={@entry.thumbnail} width="25" height="25" src={Brando.Utils.img_url(@entry.thumbnail, :smallest)} />
      </div>
    </.field>
    <.field columns={9}>
      <small class="monospace">#{@entry.id}</small>
      <br />
      <small class="monospace">
        <%= case @entry.type do %>
          <% :upload -> %>
            <%= if @entry.file do %>
              {@entry.file.filename}
            <% end %>
          <% _ -> %>
            {@entry.source_url || @entry.remote_id}
        <% end %>
      </small>
      <br />
      <small>{@entry.width}&times;{@entry.height}</small>
      <br />
      <div :if={@entry.title} class="badge mini">#{gettext("Title")}</div>
      <div :if={@entry.caption} class="badge mini">#{gettext("Caption")}</div>
    </.field>
    <.update_link entry={@entry} columns={6}>
      {@entry.title || gettext("Untitled")}
      <:outside>
        <br />
        <small class="badge">{@entry.type}</small>
      </:outside>
    </.update_link>
    <.url entry={@entry} />
    """
  end
end
