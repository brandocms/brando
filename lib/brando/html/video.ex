defmodule Brando.HTML.Video do
  import Phoenix.HTML

  @type safe_string :: {:safe, [...]}

  @doc """
  Returns a video tag with an overlay for lazyloading

  ### Opts

    - `cover`
      - `:svg`
      - `html` -> for instance, provide a rendered picture_tag
    - `poster` -> url to poster, i.e. on vimeo.
  """
  @spec video_tag(binary, map()) :: safe_string
  def video_tag(src, opts \\ %{}) do
    width = Map.get(opts, :width)
    height = Map.get(opts, :height)
    opacity = Map.get(opts, :opacity, 0)
    preload = Map.get(opts, :preload, false)
    cover = Map.get(opts, :cover, false)
    poster = Map.get(opts, :poster, false)
    play_button = Map.get(opts, :play_button, false)
    autoplay = (Map.get(opts, :autoplay, false) && "autoplay") || ""

    aspect_ratio = build_aspect_ratio_style_string(width, height)

    ~s(
      <div #{aspect_ratio}class="video-wrapper" data-smart-video>
        #{get_play_button(play_button)}
        #{get_video_cover(cover, width, height, opacity)}
        <video
          tabindex="0"
          role="presentation"
          preload="#{(preload && "none") || "auto"}"
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
             src="data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27#{
        width
      }%27%20height%3D%27#{height}%27%20style%3D%27background%3Argba%280%2C0%2C0%2C#{opacity}%29%27%2F%3E" />
         </div>
       )
    else
      ""
    end
  end

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
