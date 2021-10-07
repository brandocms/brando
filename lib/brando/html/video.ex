defmodule Brando.HTML.Video do
  import Phoenix.HTML
  alias Brando.Type.Video

  @type safe_string :: {:safe, [...]}
  @type video :: Video.t()

  @doc """
  Returns a video tag with an overlay for lazyloading

  ### Opts

    - `cover`
      - `:svg`
      - `html` -> for instance, provide a rendered picture_tag
    - `poster` -> url to poster, i.e. on vimeo.
  """
  @spec video_tag(binary | video, keyword()) :: safe_string
  def video_tag(video, opts \\ [])

  def video_tag(
        %Video{source: "vimeo", remote_id: remote_id, width: width, height: height},
        _opts
      ) do
    ~E|
      <iframe src="https://player.vimeo.com/video/<%= remote_id %>?dnt=1"
              width="<%= width %>"
              height="<%= height %>"
              frameborder="0"
              allow="autoplay; encrypted-media"
              webkitallowfullscreen
              mozallowfullscreen
              allowfullscreen>
      </iframe>
    |
  end

  def video_tag(
        %Video{source: "youtube", remote_id: remote_id, width: width, height: height},
        opts
      ) do
    autoplay = (Keyword.get(opts, :autoplay, false) && 1) || 0
    controls = (Keyword.get(opts, :controls, false) && 1) || 0
    params = "autoplay=#{autoplay}&controls=#{controls}&showinfo=0&rel=0"
    ~E|
      <iframe src="https://www.youtube.com/embed/<%= remote_id %>?<%= params %>"
              width="<%= width %>"
              height="<%= height %>"
              frameborder="0"
              allow="autoplay; encrypted-media"
              webkitallowfullscreen
              mozallowfullscreen
              allowfullscreen>
      </iframe>
    |
  end

  def video_tag(src, opts) do
    width = Keyword.get(opts, :width)
    height = Keyword.get(opts, :height)
    opacity = Keyword.get(opts, :opacity, 0)
    preload = Keyword.get(opts, :preload, false)
    preload = if preload == true, do: "auto", else: preload
    cover = Keyword.get(opts, :cover, false)
    poster = Keyword.get(opts, :poster, false)
    play_button = Keyword.get(opts, :play_button, false)
    autoplay = (Keyword.get(opts, :autoplay, false) && "autoplay") || ""

    aspect_ratio = build_aspect_ratio_style_string(width, height)

    ~s(
      <div #{aspect_ratio}class="video-wrapper" data-smart-video>
        #{get_play_button(play_button)}
        #{get_video_cover(cover, width, height, opacity)}
        <video
          #{width && "width=\"#{width}\""}
          #{height && "height=\"#{height}\""}
          alt=""
          tabindex="0"
          role="presentation"
          preload="#{(preload && preload) || "none"}"
          #{autoplay}
          muted
          loop
          playsinline
          data-video
          #{poster && "poster=\"#{poster}\""}
          #{(preload && "data-src=\"#{src}\"") || ""}
          #{(preload && "") || "src=\"#{src}\""}></video>
        <noscript>
          <video
            #{width && "width=\"#{width}\""}
            #{height && "height=\"#{height}\""}
            alt=""
            tabindex="0"
            role="presentation"
            preload="metadata"
            muted
            loop
            playsinline
            src="#{src}"></video>
        </noscript>
      </div>
      ) |> raw
  end

  defp get_video_cover(:svg, width, height, opacity) do
    if width do
      ~s(
         <div data-cover>
           <img
             width="#{width}"
             height="#{height}"
             src="data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27#{width}%27%20height%3D%27#{height}%27%20style%3D%27background%3Argba%280%2C0%2C0%2C#{opacity}%29%27%2F%3E" />
         </div>
       )
    else
      ""
    end
  end

  defp get_video_cover("false", _, _, _), do: ""
  defp get_video_cover(false, _, _, _), do: ""
  defp get_video_cover(url, _, _, _), do: url

  defp get_play_button(false), do: ""

  defp get_play_button(true),
    do: """
    <div class="video-play-button-wrapper">
      <button class="video-play-button">
        <div class="video-play-button-inside"></div>
      </button>
    </div>
    """

  defp build_aspect_ratio_style_string(nil, _), do: ""
  defp build_aspect_ratio_style_string(_, nil), do: ""

  defp build_aspect_ratio_style_string(width, height),
    do: ~s(style="--aspect-ratio: #{height / width}" )
end
