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
    - `loop`
    - `muted` -> forced on whenever `autoplay` is on, see Precedence
    - `preload`
    - `aspect_ratio`
    - `caption` -> `true` resolves to `opts[:title]`, then the record's caption
      or title
    - `progress`
    - `width`
    - `height`

  ### Precedence

  `autoplay`, `controls`, `loop`, `muted`, `preload`, `width`, `height` and
  `aspect_ratio` are also fields on `%Brando.Videos.Video{}`, set by the editor
  in the admin. An opt passed here is an override and wins; without one, the
  record's value is used; failing both, the built-in default.

  Passing `false` counts as passing — `{% video entry.video { autoplay: false } %}`
  turns autoplay off on a record that has it on.

  `muted` is the one exception to all of the above. It resolves like the others,
  but the rendered attribute is `autoplay || muted`, since browsers block
  unmuted autoplay. `muted: false` therefore cannot un-mute an autoplaying
  video — the setting only has an effect with autoplay off.
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
    >{"\n"}</iframe>
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
    >{"\n"}</iframe>
    """
  end

  def video(%{video: %Video{type: :bunny, meta: meta, status: :ready} = video, opts: opts} = assigns) do
    video_guid = get_in(meta, ["bunny", "video_guid"])
    cdn_hostname = get_bunny_cdn_hostname()

    render_video(assigns, video, opts,
      class: "video-bunny",
      src: "https://#{cdn_hostname}/#{video_guid}/playlist.m3u8",
      poster: "https://#{cdn_hostname}/#{video_guid}/thumbnail.jpg",
      aspect_ratio: "16/9"
    )
  end

  def video(%{video: %Video{type: :mux, meta: %{"mux" => %{"playback_policy" => "signed"}}}} = assigns) do
    ~H"""
    <!-- signed Mux playback requires an application token signer -->
    """
  end

  def video(%{video: %Video{type: :mux, meta: meta, status: :ready} = video, opts: opts} = assigns) do
    playback_id = get_in(meta, ["mux", "playback_id"])

    render_video(assigns, video, opts,
      class: "video-mux",
      src: "https://stream.mux.com/#{playback_id}.m3u8",
      poster: "https://image.mux.com/#{playback_id}/thumbnail.jpg",
      aspect_ratio: mux_meta_aspect_ratio(meta)
    )
  end

  def video(%{video: %Video{type: :upload} = video, opts: opts} = assigns) do
    render_video(assigns, video, opts,
      src: get_upload_video_url(video),
      poster: get_video_thumbnail(video)
    )
  end

  def video(%{video: %Video{type: :cloudflare, status: :ready} = video, opts: opts} = assigns) do
    with {:ok, src} <- Brando.Videos.Helpers.get_playback_url(video) do
      render_video(assigns, video, opts,
        class: "video-cloudflare",
        src: src,
        poster: Brando.Videos.Helpers.thumbnail_url(video)
      )
    else
      _ -> ~H"<!-- Cloudflare Stream playback is unavailable -->"
    end
  end

  def video(%{video: %Video{type: :cloudflare}} = assigns) do
    ~H"<!-- Cloudflare Stream video is not ready -->"
  end

  def video(%{video: %Video{type: :external_file} = video, opts: opts} = assigns) do
    render_video(assigns, video, opts,
      src: video.source_url || "",
      poster: get_video_thumbnail(video)
    )
  end

  def video(%{video: src, opts: opts} = assigns) when is_binary(src) do
    render_video(assigns, nil, opts,
      src: src,
      poster: Keyword.get(opts, :poster, false)
    )
  end

  def video(%{video: nil} = assigns) do
    # catch if video is nil and just include a comment
    ~H"""
    <!-- empty video component -->
    """
  end

  # One renderer for every provider. `provider` carries only what the calling
  # clause can know — the playback URL, the poster, the wrapper class, and a
  # fallback aspect ratio for providers that have one. Everything a viewer can
  # actually configure comes from `setting/4`.
  defp render_video(assigns, video, opts, provider) do
    src = Keyword.fetch!(provider, :src)
    poster = Keyword.get(provider, :poster, false)

    aspect_ratio = setting(opts, video, :aspect_ratio, Keyword.get(provider, :aspect_ratio))
    {fallback_width, fallback_height} = fallback_dimensions(aspect_ratio)
    width = setting(opts, video, :width, fallback_width)
    height = setting(opts, video, :height, fallback_height)

    orientation = (width && height && width > height && "landscape") || "portrait"
    opacity = Keyword.get(opts, :opacity, 0)
    cover = Keyword.get(opts, :cover, false)
    progress = Keyword.get(opts, :progress, false)
    play_button = Keyword.get(opts, :play_button, false)

    assigns =
      assigns
      |> assign(:class, Keyword.get(provider, :class, "video-file"))
      |> assign(:orientation, orientation)
      |> assign(:aspect_ratio, build_aspect_ratio_style_string(aspect_ratio, width, height))
      |> assign(:autoplay, setting(opts, video, :autoplay, false))
      |> assign(:muted, setting(opts, video, :muted, false))
      |> assign(:controls, setting(opts, video, :controls, false))
      |> assign(:poster, validate_poster(poster))
      |> assign(:width, width)
      |> assign(:height, height)
      |> assign(:preload, video |> setting_preload(opts) |> preload_value())
      |> assign(:progress, progress)
      |> assign(:src, src)
      |> assign(:loop, setting(opts, video, :loop, true))
      |> assign(:play_button, play_button)
      |> assign(:video_cover, get_video_cover(cover, width, height, opacity))
      |> assign(:caption, caption(opts, video))
      |> assign_new(:cover, fn -> nil end)

    ~H"""
    <div
      class={"video-wrapper #{@class}"}
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
        muted={@autoplay || @muted}
        loop={@loop}
        playsinline
        controls={@controls}
        data-video
        poster={@poster}
        style={@aspect_ratio}
        data-src={@preload && @src}
        src={!@preload && @src}
      >{"\n  "}</video>

      <noscript>
        <video
          width={@width}
          height={@height}
          alt=""
          tabindex="0"
          preload="metadata"
          muted={@autoplay || @muted}
          loop={@loop}
          playsinline
          src={@src}
        >{"\n    "}</video>
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

  # Precedence: an explicit opt at the call site, then the editor's setting on
  # the record, then the built-in default.
  #
  # `Keyword.fetch/2` rather than `Keyword.get/3`, and a nil test rather than
  # `||`, because `false` is a real value at both levels. "Not passed" and
  # "passed as false" are different questions, and so are "the editor never
  # touched this" (nil — the columns carry no default) and "the editor turned it
  # off" (false). The `||` chains this replaces read both as absent, which is
  # why a record with `loop: false` still looped.
  defp setting(opts, video, key, default) do
    opts
    |> Keyword.fetch(key)
    |> from_opts_or_record(video, key, default)
  end

  defp from_opts_or_record({:ok, value}, _video, _key, _default), do: value
  defp from_opts_or_record(:error, nil, _key, default), do: default
  defp from_opts_or_record(:error, video, key, default), do: video |> Map.get(key) |> or_default(default)

  defp or_default(nil, default), do: default
  defp or_default(value, _default), do: value

  # `preload` resolves like any other setting, but `true` is shorthand for the
  # HTML attribute value rather than a value in its own right.
  defp setting_preload(video, opts), do: setting(opts, video, :preload, false)

  defp preload_value(true), do: "auto"
  defp preload_value(preload), do: preload

  # Captions stay opt-in — a record carrying a caption does not start rendering
  # a `<figcaption>` on templates that never asked for one. What `caption: true`
  # resolves *to* is what gained the record: it used to see only `opts[:title]`,
  # so an editor's caption was unreachable from the tag syntax.
  defp caption(opts, video) do
    opts
    |> Keyword.get(:caption, false)
    |> resolve_caption(opts, video)
  end

  defp resolve_caption(false, _opts, _video), do: false

  defp resolve_caption(true, opts, video) do
    opts |> Keyword.get(:title) |> or_default(record_caption(video))
  end

  defp resolve_caption(caption, _opts, _video), do: caption

  defp record_caption(nil), do: false
  defp record_caption(video), do: video.caption |> or_default(video.title) |> or_default(false)

  # Providers know their ratio but not always their pixel dimensions, so the
  # ratio is the last-resort source for width/height. Kept total: the string can
  # come from Mux meta, which is not guaranteed to be two integers, and the
  # `String.to_integer/1` this replaces raised on anything else.
  defp fallback_dimensions(nil), do: {nil, nil}
  defp fallback_dimensions(aspect_ratio), do: aspect_ratio |> String.split("/") |> parsed_dimensions()

  defp parsed_dimensions([width, height]) do
    with {width, ""} <- Integer.parse(String.trim(width)),
         {height, ""} <- Integer.parse(String.trim(height)),
         true <- width > 0 and height > 0 do
      {width, height}
    else
      _ -> {nil, nil}
    end
  end

  defp parsed_dimensions(_parts), do: {nil, nil}

  # Mux stores its ratio as "16:9"; the record's own `aspect_ratio` is already
  # in the "16/9" CSS form and wins via `setting/4`. This is the fallback for
  # rows written before that field existed.
  defp mux_meta_aspect_ratio(meta) do
    meta |> get_in(["mux", "aspect_ratio"]) |> mux_ratio_to_css() |> or_default("16/9")
  end

  defp mux_ratio_to_css(aspect_ratio) when is_binary(aspect_ratio), do: String.replace(aspect_ratio, ":", "/")
  defp mux_ratio_to_css(_aspect_ratio), do: nil

  defp get_upload_video_url(%Video{file: %Brando.Files.File{} = file}) do
    Brando.Utils.media_url(file)
  end

  defp get_upload_video_url(%Video{remote_id: remote_id}) when is_binary(remote_id) do
    Brando.Utils.media_url(remote_id)
  end

  defp get_upload_video_url(_), do: ""

  defp get_video_thumbnail(%Video{thumbnail: %Brando.Images.Image{} = img}) do
    Brando.Utils.media_url(img.path)
  end

  defp get_video_thumbnail(_), do: false

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

  defp get_video_cover("true", _, _, _), do: nil
  defp get_video_cover(true, _, _, _), do: nil
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

  defp get_bunny_cdn_hostname do
    :brando
    |> Application.get_env(Brando.Videos.Uploaders.Bunny, [])
    |> Keyword.get(:cdn_hostname, "")
  end
end
