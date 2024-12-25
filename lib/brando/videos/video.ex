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
      query %{order: [{:desc, :id}]}
      filter label: t("Path"), filter: "path"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.field columns={2}>
      <div class="padded">
        <img
          :if={@entry.cover}
          width="25"
          height="25"
          src={Brando.Utils.img_url(@entry.cover, :smallest)}
        />
        <img :if={@entry.thumbnail_url} width="25" height="25" src={@entry.thumbnail_url} />
      </div>
    </.field>
    <.field columns={9}>
      <small class="monospace">#{@entry.id}</small>
      <br />
      <small class="monospace">
        <%= if @entry.filename do %>
          {@entry.filename}
        <% else %>
          {@entry.url}
        <% end %>
      </small>
      <br />
      <small>{@entry.width}&times;{@entry.height}</small>
      <br />
      <div :if={@entry.title} class="badge mini">#{gettext("Title")}</div>
      <div :if={@entry.alt} class="badge mini">Alt</div>
    </.field>
    <.update_link entry={@entry} columns={6}>
      {@entry.title}
      <:outside>
        <%= if @entry.category do %>
          <br />
          <small class="badge">{@entry.category.name}</small>
        <% end %>
      </:outside>
    </.update_link>
    <.url entry={@entry} />
    """
  end
end
