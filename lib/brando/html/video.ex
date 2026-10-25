defmodule Brando.HTML.Video do
  use Phoenix.Component
  alias Brando.Videos.Video

  @type safe_string :: {:safe, [...]}
  @type video :: Video.t()

  @doc """
  Returns a video tag with an overlay for lazyloading

  ### Opts

    - `cover`
      - `:svg`
      - `html` -> for instance, provide a rendered picture_tag (safe markup;
        any other string gets the `:svg` placeholder)
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
    - `play_button` -> `true`, or a string to use as the button's label
    - `opacity` -> background opacity of the `:svg` cover
    - `width`
    - `height`
    - `quality` -> `:auto`, `:hls`, `:mp4_360`, `:mp4_480`, `:mp4_720` or
      `:mp4_1080`: whether a Bunny video streams or plays an MP4, see
      `Brando.Videos.Playback`

  ### Precedence

  `autoplay`, `controls`, `loop`, `muted`, `preload`, `width`, `height` and
  `aspect_ratio` are also fields on `%Brando.Videos.Video{}`, set by the editor
  in the admin. An opt passed here is an override and wins; without one, the
  record's value is used; failing both, the built-in default.

  `cover`, `opacity`, `progress` and `play_button` resolve the same way, but
  their second step is a virtual field: they are block-level presentation
  settings that `Brando.Content.OverrideResolver` merges onto the record when a
  video block renders, and are simply nil for a video used anywhere else.

  Passing `false` counts as passing — `{% video entry.video { autoplay: false } %}`
  turns autoplay off on a record that has it on.

  `quality` turns this order around: it is the developer's default for the
  placement, so the editor's choice on the record (or a block's or gallery
  object's, merged onto it) wins, and the opt applies only where they left it
  empty.

  `muted` is the other exception. It resolves like the others,
  but the rendered attribute is `autoplay || muted`, since browsers block
  unmuted autoplay. `muted: false` therefore cannot un-mute an autoplaying
  video — the setting only has an effect with autoplay off.
  """
  def video(assigns)

  # These two took `%{assigns: %{video: …}}` while every other clause takes
  # `%{video: …, opts: …}`. A function component is handed its assigns directly,
  # never wrapped, so neither clause could match and a Vimeo or YouTube record
  # reaching `<.video>` — from `{% video entry.video %}` or a gallery — raised
  # FunctionClauseError. `Brando.Villain.Parser.video/2` renders those two types
  # itself, which is why nothing hit it sooner.
  def video(%{video: %Video{type: :vimeo, width: width, height: height} = video} = assigns) do
    assigns =
      assigns
      |> assign(:src, Brando.Videos.VimeoURL.embed_url(video, dnt: 1))
      |> assign(:width, width)
      |> assign(:height, height)

    ~H"""
    <iframe
      src={@src}
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

  def video(%{video: %Video{type: :youtube, remote_id: remote_id, width: width, height: height}, opts: opts} = assigns) do
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

    {_format, src} =
      Brando.Videos.Playback.source(video,
        quality: Keyword.get(opts, :quality),
        controls: setting(opts, video, :controls, false),
        play_button: setting(opts, video, :play_button, false)
      )

    render_video(assigns, video, opts,
      class: "video-bunny",
      src: src,
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
    case Brando.Videos.Helpers.get_playback_url(video) do
      {:ok, src} ->
        render_video(assigns, video, opts,
          class: "video-cloudflare",
          src: src,
          poster: Brando.Videos.Helpers.thumbnail_url(video)
        )

      _ ->
        ~H"<!-- Cloudflare Stream playback is unavailable -->"
    end
  end

  def video(%{video: %Video{type: :cloudflare}} = assigns) do
    ~H"<!-- Cloudflare Stream video is not ready -->"
  end

  def video(%{video: %Video{type: :vimeo_account, status: :ready} = video, opts: opts} = assigns) do
    case Brando.Videos.Helpers.get_playback_url(video) do
      {:ok, src} ->
        render_video(assigns, video, opts,
          class: "video-vimeo",
          src: src,
          poster: Brando.Videos.Helpers.thumbnail_url(video)
        )

      # The account has no `video_files` scope or plan, so there is no file
      # link to hand <video>. Vimeo's player still plays it.
      _ ->
        assigns =
          assigns
          |> assign(:src, Brando.Videos.Uploaders.Vimeo.embed_url(video, [dnt: 1] ++ vimeo_player_params(opts, video)))
          |> assign_iframe_size(opts, video)

        ~H"""
        <iframe
          src={@src}
          width={@width}
          height={@height}
          frameborder="0"
          allow="autoplay; fullscreen; picture-in-picture"
          allowfullscreen
        >{"\n"}</iframe>
        """
    end
  end

  def video(%{video: %Video{type: :vimeo_account}} = assigns) do
    ~H"<!-- Vimeo video is not ready -->"
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

  # Everything above is a specific record shape; this is what happens to the
  # rest. Without it the clause list is a partial function on a value a template
  # author cannot inspect, and a miss is a FunctionClauseError raised out of
  # `Brando.Villain.Tags.Video.render/2` — which, in the admin, is inside live
  # preview, so it takes the entry form down mid-save along with every unsaved
  # change in it.
  #
  # Two shapes reach here in practice, and neither is an authoring error:
  #
  #   * `%Ecto.Association.NotLoaded{}` — `{% video entry.listing_video %}` where
  #     the preview query did not preload the association. Observed in
  #     production against `MyApp.Projects.Project.listing_video`.
  #   * a provider record that is not `status: :ready` — the `:mux`, `:bunny`
  #     and `:cloudflare` clauses all require it, because there is no playback
  #     id to render until the provider's webhook lands. A video is in exactly
  #     that state for the whole window between upload and transcode.
  #
  # Rendering nothing is the same answer `nil` already gets, and for the same
  # reason: there is no video to show yet. A record that will never become
  # playable is a data problem the video list surfaces, not something a page
  # render should crash over.
  def video(assigns) do
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
    # A poster passed in (a video block's) wins over the provider's thumbnail
    poster =
      case Keyword.get(opts, :poster) do
        poster when is_binary(poster) and poster != "" -> poster
        _ -> Keyword.get(provider, :poster, false)
      end

    aspect_ratio = setting(opts, video, :aspect_ratio, provider_aspect_ratio(opts, video, provider))
    {width, height} = dimensions(opts, video, aspect_ratio)

    orientation = (width && height && width > height && "landscape") || "portrait"
    opacity = setting(opts, video, :opacity, 0)
    cover = setting(opts, video, :cover, false)
    progress = setting(opts, video, :progress, false)
    play_button = setting(opts, video, :play_button, false)

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
  # a `<figcaption>` on templates that never asked for one. `caption: true`
  # resolves to `opts[:title]`, falling back to the record's caption, so an
  # editor's caption is reachable from the tag syntax.
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
  defp fallback_dimensions(aspect_ratio), do: aspect_ratio |> String.split(["/", ":"]) |> parsed_dimensions()

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

  # A provider's ratio (Bunny's 16/9) is a guess for a video whose size is
  # unknown. A width and height passed together give the ratio; failing that,
  # the record's own size does, so overriding one dimension keeps its shape.
  defp provider_aspect_ratio(opts, video, provider) do
    record_size = if video, do: {Map.get(video, :width), Map.get(video, :height)}, else: {nil, nil}

    cond do
      known_size?({Keyword.get(opts, :width), Keyword.get(opts, :height)}) -> nil
      known_size?(record_size) -> record_size |> Tuple.to_list() |> Enum.join("/")
      true -> Keyword.get(provider, :aspect_ratio)
    end
  end

  # A caller's single dimension takes the other from the ratio, so the
  # attributes and orientation keep the video's shape
  defp dimensions(opts, video, aspect_ratio) do
    {ratio_width, ratio_height} = fallback_dimensions(aspect_ratio)

    case {Keyword.get(opts, :width), Keyword.get(opts, :height), ratio_width} do
      {width, nil, ratio_width} when is_integer(width) and is_integer(ratio_width) ->
        {width, round(width * ratio_height / ratio_width)}

      {nil, height, ratio_width} when is_integer(height) and is_integer(ratio_width) ->
        {round(height * ratio_width / ratio_height), height}

      _ ->
        {setting(opts, video, :width, ratio_width), setting(opts, video, :height, ratio_height)}
    end
  end

  # An embed's size, as a <video>'s: one dimension passed takes the other from
  # the video's ratio
  defp assign_iframe_size(assigns, opts, video) do
    aspect_ratio = setting(opts, video, :aspect_ratio, provider_aspect_ratio(opts, video, []))
    {width, height} = dimensions(opts, video, aspect_ratio)

    assigns
    |> assign(:width, width)
    |> assign(:height, height)
  end

  defp known_size?({width, height}), do: is_integer(width) and is_integer(height) and width > 0 and height > 0

  # Vimeo's player defaults are its own (no loop), so only what the caller or
  # the record sets is passed; autoplay needs muted, as in <video>. Controls
  # stay Vimeo's: its `controls=0` hides the play button too, where Brando's
  # "controls off" still leaves a way to play.
  defp vimeo_player_params(opts, video) do
    autoplay = setting(opts, video, :autoplay, nil)

    [
      autoplay: autoplay,
      muted: if(autoplay, do: true, else: setting(opts, video, :muted, nil)),
      loop: setting(opts, video, :loop, nil)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map(fn {key, value} -> {key, if(value, do: 1, else: 0)} end)
  end

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
         <div data-cover aria-hidden="true">
           <img
             width="#{width}"
             height="#{height}"
             alt=""
             src="data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27#{width}%27%20height%3D%27#{height}%27%20style%3D%27background%3Argba%280%2C0%2C0%2C#{opacity}%29%27%2F%3E" />
         </div>
       ) |> Phoenix.HTML.raw()
    else
      "" |> Phoenix.HTML.raw()
    end
  end

  # The editor stores `cover` as a string ("false" or "svg"), so the block's own
  # setting arrives as "svg" where a template would pass :svg.
  defp get_video_cover("svg", width, height, opacity), do: get_video_cover(:svg, width, height, opacity)

  defp get_video_cover("true", _, _, _), do: nil
  defp get_video_cover(true, _, _, _), do: nil
  defp get_video_cover("false", _, _, _), do: nil
  defp get_video_cover(false, _, _, _), do: nil
  defp get_video_cover(nil, _, _, _), do: nil

  # Any other string, such as the thumbnail URL a Villain-era block could hold,
  # gets the placeholder Brando drew for it before 0.54, rather than being
  # printed as text. Markup a template passes (`Phoenix.HTML.raw/1`, a
  # rendered component) is used as it is.
  defp get_video_cover(cover, width, height, opacity) when is_binary(cover),
    do: get_video_cover(:svg, width, height, opacity)

  defp get_video_cover(html, _, _, _), do: html

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

  # A set ratio reads "16/9" (or "16:9", as Mux and older records write it).
  # `--aspect-ratio` is height over width, as in the clause above — embeds pad
  # by it — and `--aspect-ratio-division` is CSS `aspect-ratio`'s width/height.
  # A ratio that doesn't parse is ignored for the video's own dimensions.
  defp build_aspect_ratio_style_string(aspect_ratio, width, height) do
    with [ratio_width, ratio_height] <- aspect_ratio |> String.split(["/", ":"]) |> Enum.map(&String.trim/1),
         {w, ""} when w > 0 <- Float.parse(ratio_width),
         {h, ""} when h > 0 <- Float.parse(ratio_height) do
      ~s(--aspect-ratio: #{h / w}; --aspect-ratio-division: #{ratio_width}/#{ratio_height};)
    else
      _ -> build_aspect_ratio_style_string(nil, width, height)
    end
  end

  defp get_bunny_cdn_hostname do
    :brando
    |> Application.get_env(Brando.Videos.Uploaders.Bunny, [])
    |> Keyword.get(:cdn_hostname, "")
  end
end
