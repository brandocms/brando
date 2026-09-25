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
  import Brando.Blueprint.Listings.Components.Core

  trait :creator, derived: [:status, :remote_id, :meta, :width, :height, :aspect_ratio, :duration]
  trait :timestamped
  trait :soft_delete

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
    attribute :type, :enum, values: [:upload, :external_file, :vimeo, :youtube, :mux, :bunny, :cloudflare]
    attribute :title, :text
    attribute :caption, :text
    attribute :aspect_ratio, :string
    attribute :width, :integer
    attribute :height, :integer
    attribute :duration, :string
    attribute :autoplay, :boolean
    attribute :preload, :boolean
    attribute :loop, :boolean
    attribute :controls, :boolean
    attribute :muted, :boolean
    attribute :source_url, :text
    attribute :remote_id, :text
    attribute :config_target, :text
    attribute :folder_id, :integer

    attribute :status, :enum,
      values: [:uploading, :processing, :ready, :errored],
      default: :ready

    attribute :meta, :map, default: %{}

    # Where the video is used, filled in by the listing (see `Brando.Videos.put_usage/1`).
    attribute :usage, :map, virtual: true

    # Block-level presentation settings, declared on
    # `Brando.Villain.Blocks.VideoBlock.Data` and merged onto the video at render
    # time by `Brando.Content.OverrideResolver`. They describe how *this
    # placement* of the video should render, never the video itself, so they are
    # virtual — nothing here is persisted on the video record, and nothing here
    # is set for a video outside a video block. The playback fields
    # (`autoplay`, `preload`, `loop`, `muted`, `controls`) are real columns
    # above: those the editor sets on the record and the block overrides.
    attribute :poster, :text, virtual: true
    attribute :opacity, :integer, virtual: true, default: 0
    attribute :play_button, :boolean, virtual: true, default: false
    attribute :progress, :boolean, virtual: true, default: false
    attribute :cover, :string, virtual: true, default: "false"
    attribute :cover_image, :any, virtual: true
  end

  assets do
    asset :file, :file, cfg: :config_target
    asset :thumbnail, :image, cfg: @thumbnail_cfg
  end

  listings do
    listing do
      query %{order: [{:desc, :id}], preload: [:file, :thumbnail]}
      filter label: t("Title or source"), key: "path"
      filter label: t("Not in use"), key: "unused", type: :boolean
      decorate &__MODULE__.put_usage/1
      component &__MODULE__.listing_row/1
    end
  end

  forms do
    form do
      tab t("Content") do
        fieldset do
          size :half
          input :title, :text, label: t("Title")
          input :caption, :text, label: t("Caption")

          input :type, :select,
            label: t("Type"),
            options: [
              %{label: "Upload", value: :upload},
              %{label: "External file", value: :external_file},
              %{label: "Vimeo", value: :vimeo},
              %{label: "YouTube", value: :youtube},
              %{label: "Mux", value: :mux},
              %{label: "Bunny", value: :bunny},
              %{label: "Cloudflare Stream", value: :cloudflare}
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
          input :muted, :toggle, label: t("Muted")
          input :file, :file, label: t("Video file")
          input :thumbnail, :image, label: t("Thumbnail")
        end
      end
    end
  end

  # A local capture: the listing DSL keeps the function at compile time, and a
  # capture of `Brando.Videos` would make this Blueprint compile against the
  # whole videos context (issue #2737).
  @doc false
  def put_usage(videos), do: Brando.Videos.put_usage(videos)

  def listing_row(assigns) do
    assigns = assign(assigns, :title, Brando.Videos.display_title(assigns.entry))

    ~H"""
    <.field columns={1} class="library-thumbnail library-video-thumbnail">
      <button
        type="button"
        class="library-video-play"
        phx-click="play_video"
        phx-value-id={@entry.id}
        aria-label={gettext("Play %{title}", title: @title || gettext("Untitled"))}
      >
        <img
          :if={@entry.thumbnail}
          width="64"
          height="52"
          alt=""
          src={Brando.Utils.img_url(@entry.thumbnail, :smallest, prefix: Brando.Utils.media_url())}
        />
        <Brando.HTML.Icon.icon :if={!@entry.thumbnail} name="hero-film" />
        <span class="library-video-play-icon" aria-hidden="true"><Brando.HTML.Icon.icon name="hero-play-solid" /></span>
      </button>
    </.field>
    <.update_link entry={@entry} columns={8} class="library-image-info library-video-info" skip_style>
      <:before>
        <%!-- The title is renamed in place; the empty click keeps the row from being selected. --%>
        <form
          id={"video-rename-#{@entry.id}"}
          class="library-video-rename"
          phx-submit="rename_video"
          phx-change="rename_video"
          phx-click={%Phoenix.LiveView.JS{}}
        >
          <input type="hidden" name="video_id" value={@entry.id} />
          <input
            type="text"
            name="title"
            value={@title}
            placeholder={gettext("Untitled")}
            aria-label={gettext("Title")}
            autocomplete="off"
            phx-debounce="blur"
          />
        </form>
      </:before>
      <span class="library-image-title">
        <%= case @entry.type do %>
          <% :upload -> %>
            {if @entry.file, do: URI.decode(@entry.file.filename)}
          <% _ -> %>
            {video_source(@entry)}
        <% end %>
      </span>
      <:outside>
        <div class="library-image-meta">
          <span class="library-format">{video_type_label(@entry.type)}</span>
          <span :if={@entry.width && @entry.height}>{@entry.width} × {@entry.height}</span>
          <span :if={@entry.duration && @entry.duration != ""}>{short_duration(@entry.duration)}</span>
          <span :if={@entry.type == :upload && @entry.file}>{Brando.Utils.human_size(@entry.file.filesize)}</span>
        </div>
        <div :if={is_list(@entry.usage)} class="library-video-usage">
          <%= if @entry.usage == [] do %>
            <span class="library-video-unused">{gettext("Not in use")}</span>
          <% else %>
            <span>{gettext("Used in")}</span>
            <%= for {usage, index} <- Enum.with_index(@entry.usage) do %>
              <.link :if={usage.url} navigate={usage.url}>{usage.label}</.link><span :if={!usage.url}>{usage.label}</span><span
                :if={index < length(@entry.usage) - 1}
                aria-hidden="true"
              >,</span>
            <% end %>
          <% end %>
        </div>
      </:outside>
    </.update_link>
    """
  end

  # "00:01:05" reads as "1:05"; hours stay when there are any.
  defp short_duration(duration) do
    case String.split(duration, ":") do
      ["00", "0" <> minutes, seconds] -> "#{minutes}:#{seconds}"
      ["00", minutes, seconds] -> "#{minutes}:#{seconds}"
      _ -> duration
    end
  end

  defp video_source(%{source_url: url}) when is_binary(url) and url != "" do
    uri = URI.parse(url)

    [uri.host, uri.path && Path.basename(uri.path)]
    |> Enum.reject(&(&1 in [nil, "", "/"]))
    |> Enum.join("/")
    |> URI.decode()
  end

  defp video_source(video), do: video.remote_id

  defp video_type_label(:upload), do: gettext("Uploaded file")
  defp video_type_label(:external_file), do: gettext("External file")
  defp video_type_label(:youtube), do: "YouTube"
  defp video_type_label(:vimeo), do: "Vimeo"
  defp video_type_label(type), do: type |> to_string() |> String.capitalize()
end
