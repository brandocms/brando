defmodule Brando.HTML.Video do
  use Gettext, backend: Brando.Gettext
  use Phoenix.Component
  alias Brando.Videos.Video

  @type safe_string :: {:safe, [...]}
  @type video :: Video.t()

  @doc """
  Returns a video tag with an overlay for lazyloading

  ### Opts

    - `cover`
      - `:svg`
      - `html` -> for instance, provide a rendered picture_tag
    - `poster` -> url to poster, i.e. on vimeo.
    - `autoplay`
    - `controls`
    - `progress`
    - `width`
    - `height`
  """
  def video(assigns)

  def video(%{assigns: %{video: %Video{type: :vimeo, remote_id: remote_id, width: width, height: height}} = assigns}) do
    assigns =
      assigns
      |> assign(:remote_id, remote_id)
      |> assign(:width, width)
      |> assign(:height, height)

    ~H"""
    <iframe
      src={"https://player.vimeo.com/video/#{@remote_id}?dnt=1"}
      width={@width}
      height={@height}
      frameborder="0"
      allow="autoplay; encrypted-media"
      webkitallowfullscreen
      mozallowfullscreen
      allowfullscreen
    >
    </iframe>
    """
  end

  def video(%{
        assigns:
          %{video: %Video{type: :youtube, remote_id: remote_id, width: width, height: height}, opts: opts} = assigns
      }) do
    autoplay = (Keyword.get(opts, :autoplay, false) && 1) || 0
    controls = (Keyword.get(opts, :controls, false) && 1) || 0
    params = "autoplay=#{autoplay}&controls=#{controls}&showinfo=0&rel=0"

    assigns =
      assigns
      |> assign(:remote_id, remote_id)
      |> assign(:params, params)
      |> assign(:width, width)
      |> assign(:height, height)

    ~H"""
    <iframe
      src={"https://www.youtube.com/embed/#{@remote_id}?#{@params}"}
      width={@width}
      height={@height}
      frameborder="0"
      allow="autoplay; encrypted-media"
      webkitallowfullscreen
      mozallowfullscreen
      allowfullscreen
    >
    </iframe>
    """
  end

  def video(%{video: src, opts: opts} = assigns) when is_binary(src) do
    width = Keyword.get(opts, :width)
    height = Keyword.get(opts, :height)
    orientation = (width > height && "landscape") || "portrait"
    opacity = Keyword.get(opts, :opacity, 0)
    preload = Keyword.get(opts, :preload, false)
    preload = if preload == true, do: "auto", else: preload
    cover = Keyword.get(opts, :cover, false)
    poster = Keyword.get(opts, :poster, false)
    progress = Keyword.get(opts, :progress, false)
    play_button = Keyword.get(opts, :play_button, false)
    autoplay = Keyword.get(opts, :autoplay, false)
    controls = Keyword.get(opts, :controls, false)
    aspect_ratio = Keyword.get(opts, :aspect_ratio, nil)
    aspect_ratio = build_aspect_ratio_style_string(aspect_ratio, width, height)
    loop = Keyword.get(opts, :loop, true)

    caption =
      case Keyword.get(opts, :caption, false) do
        false -> false
        true -> Keyword.get(opts, :title, false)
        caption -> caption
      end

    assigns =
      assigns
      |> assign(:orientation, orientation)
      |> assign(:aspect_ratio, aspect_ratio)
      |> assign(:autoplay, autoplay)
      |> assign(:controls, controls)
      |> assign(:poster, validate_poster(poster))
      |> assign(:width, width)
      |> assign(:height, height)
      |> assign(:preload, preload)
      |> assign(:progress, progress)
      |> assign(:src, src)
      |> assign(:loop, loop)
      |> assign(:play_button, play_button)
      |> assign(:video_cover, get_video_cover(cover, width, height, opacity))
      |> assign(:caption, caption)
      |> assign_new(:cover, fn ->
        nil
      end)

    ~H"""
    <div
      class="video-wrapper video-file"
      data-smart-video
      data-orientation={@orientation}
      data-progress={@progress}
      data-preload={@preload && @src}
      data-src={@src}
      data-autoplay={@autoplay}
      data-controls={@controls}
      style={@aspect_ratio}
    >
      <video
        width={@width}
        height={@height}
        alt=""
        tabindex="0"
        preload="auto"
        autoplay={@autoplay}
        muted={@autoplay}
        loop={@loop}
        playsinline
        controls={@controls}
        data-video
        poster={@poster}
        style={@aspect_ratio}
        data-src={@preload && @src}
        src={!@preload && @src}
      >
      </video>

      <noscript>
        <video
          width={@width}
          height={@height}
          alt=""
          tabindex="0"
          preload="metadata"
          muted={@autoplay}
          loop={@loop}
          playsinline
          src={@src}
        >
        </video>
      </noscript>

      {get_play_button(@play_button)}

      <%= if @cover do %>
        <div data-cover>
          {render_slot(@cover)}
        </div>
      <% else %>
        <%= if @video_cover do %>
          {@video_cover}
        <% end %>
      <% end %>
      <.figcaption_tag :if={@caption} caption={@caption} />
    </div>
    """
  end

  def video(%{video: nil} = assigns) do
    # catch if video is nil and just include a comment
    ~H"""
    <!-- empty video component -->
    """
  end

  defp figcaption_tag(assigns) do
    ~H"""
    <figcaption>{Phoenix.HTML.raw(@caption)}</figcaption>
    """
  end

  defp validate_poster("/" <> _ = url), do: url
  defp validate_poster("http" <> _ = url), do: url
  defp validate_poster(_), do: false

  defp get_video_cover(:svg, width, height, opacity) do
    if width do
      ~s(
         <div data-cover>
           <img
             width="#{width}"
             height="#{height}"
             alt="#{gettext("Video cover image")}"
             src="data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27#{width}%27%20height%3D%27#{height}%27%20style%3D%27background%3Argba%280%2C0%2C0%2C#{opacity}%29%27%2F%3E" />
         </div>
       ) |> Phoenix.HTML.raw()
    else
      "" |> Phoenix.HTML.raw()
    end
  end

  defp get_video_cover("false", _, _, _), do: nil
  defp get_video_cover(false, _, _, _), do: nil
  defp get_video_cover(url, _, _, _), do: url

  defp get_play_button(false), do: Phoenix.HTML.raw("")

  defp get_play_button(true),
    do:
      """
      <div class="video-play-button-wrapper">
        <button class="video-play-button">
          <div class="video-play-button-inside">▶︎</div>
        </button>
      </div>
      """
      |> Phoenix.HTML.raw()

  defp get_play_button(text),
    do:
      """
      <div class="video-play-button-wrapper">
        <button class="video-play-button">
          <div class="video-play-button-inside">#{text}</div>
        </button>
      </div>
      """
      |> Phoenix.HTML.raw()

  defp build_aspect_ratio_style_string(nil, nil, _), do: nil
  defp build_aspect_ratio_style_string(nil, _, nil), do: nil
  defp build_aspect_ratio_style_string(nil, 0, _), do: nil
  defp build_aspect_ratio_style_string(nil, _, 0), do: nil
  defp build_aspect_ratio_style_string(nil, 0, 0), do: nil

  defp build_aspect_ratio_style_string(nil, width, height) do
    ~s(--aspect-ratio: #{height / width}; --aspect-ratio-division: #{width}/#{height};)
  end

  defp build_aspect_ratio_style_string(aspect_ratio, _, _),
    do: ~s(--aspect-ratio: #{aspect_ratio}; --aspect-ratio-division: #{aspect_ratio};)
end
