defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  @type alert_levels :: :default | :primary | :info | :success | :warning | :danger
  @type safe_string :: {:safe, [...]}
  @type conn :: Plug.Conn.t()

  alias Brando.Utils

  import Phoenix.HTML
  import Phoenix.HTML.Tag

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.HTML
    end
  end

  defdelegate img_tag(field, opts), to: Brando.HTML.Images
  defdelegate img_tag(field, size, opts), to: Brando.HTML.Images
  defdelegate meta_tag(tuple), to: Brando.Meta.HTML
  defdelegate meta_tag(name, content), to: Brando.Meta.HTML
  defdelegate picture_tag(field, opts), to: Brando.HTML.Images
  defdelegate render_json_ld(conn), to: Brando.JSONLD.HTML
  defdelegate render_json_ld(type, data), to: Brando.JSONLD.HTML
  defdelegate render_meta(conn), to: Brando.Meta.HTML

  defp get_video_cover(:svg, width, height, opacity) do
    if width do
      ~s(
         <div data-cover>
           <img
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

  defp get_video_cover(url, _, _, _) do
    url
  end

  @doc """
  Returns a video tag with an overlay for lazyloading

  ### Opts

    - `cover`
      - `:svg`
      - `html` -> for instance, provide a rendered picture_tag
    - `poster` -> url to poster, i.e. on vimeo.
  """
  @spec video_tag(binary, map()) :: safe_string
  def video_tag(src, opts) do
    width = Map.get(opts, :width)
    height = Map.get(opts, :height)
    opacity = Map.get(opts, :opacity, 0)
    preload = Map.get(opts, :preload, false)
    cover = Map.get(opts, :cover, false)
    poster = Map.get(opts, :poster, false)
    autoplay = (Map.get(opts, :autoplay, false) && "autoplay") || ""

    ~s(
      <div class="video-wrapper" data-smart-video>
        #{get_video_cover(cover, width, height, opacity)}
        <video
          tabindex="0"
          role="presentation"
          preload="auto"
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

  @doc """
  Returns `active` if `conn`'s `full_path` matches `current_path`.
  """
  @spec active(conn, binary) :: binary
  def active(conn, url_to_match, add_class? \\ nil) do
    result = (add_class? && ~s(class="active")) || "active"
    (Utils.active_path?(conn, url_to_match) && result) || ""
  end

  @doc """
  Render markdown as html raw
  """
  def render_markdown(markdown, opts \\ [breaks: true])
  def render_markdown(nil, _), do: ""
  def render_markdown(markdown, opts), do: markdown |> Earmark.as_html!(opts) |> raw

  @doc """
  Zero pad `val` as a binary.

  ## Example

      iex> zero_pad(5)
      "005"

  """
  @spec zero_pad(val :: String.t() | Integer.t(), count :: Integer.t()) :: String.t()
  def zero_pad(str, count \\ 3)
  def zero_pad(val, count) when is_binary(val), do: String.pad_leading(val, count, "0")

  def zero_pad(val, count) when is_integer(val),
    do: String.pad_leading(Integer.to_string(val), count, "0")

  @doc """
  Split `full_name` and return first name
  """
  def first_name(full_name) do
    full_name
    |> String.split()
    |> hd()
  end

  @doc """
  Returns a red X if value is nil, or a check if the value is truthy
  """
  @spec check_or_x(val :: nil | bool) :: String.t()
  def check_or_x(nil), do: ~s(<i class="icon-centered fa fa-times text-danger"></i>)
  def check_or_x(false), do: ~s(<i class="icon-centered fa fa-times text-danger"></i>)
  def check_or_x(_), do: ~s(<i class="icon-centered fa fa-check text-success"></i>)

  @doc """
  Displays a banner informing about cookie laws
  """
  def cookie_law(_conn, text, opts \\ []) do
    text = raw(text)
    button_text = Keyword.get(opts, :button_text, "OK")
    info_link = Keyword.get(opts, :info_link, "/cookies")
    info_text = Keyword.get(opts, :info_text)

    ~E"""
    <div class="container cookie-container">
      <div class="cookie-container-inner">
        <div class="cookie-law">
          <div class="cookie-law-text">
            <p><%= text %></p>
          </div>
          <div class="cookie-law-buttons">
            <button class="dismiss-cookielaw">
              <%= button_text %>
            </button>
            <%= if info_text do %>
            <a href="<%= info_link %>" class="info-cookielaw">
              <%= info_text %>
            </a>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Output Google Analytics code for `code`

  ## Example

      google_analytics("UA-XXXXX-X")

  """
  @spec google_analytics(ua_code :: String.t()) :: safe_string()
  def google_analytics(ua_code) do
    content =
      """
      (function(b,o,i,l,e,r){b.GoogleAnalyticsObject=l;b[l]||(b[l]=
      function(){(b[l].q=b[l].q||[]).push(arguments)});b[l].l=+new Date;
      e=o.createElement(i);r=o.getElementsByTagName(i)[0];
      e.src='//www.google-analytics.com/analytics.js';
      r.parentNode.insertBefore(e,r)}(window,document,'script','ga'));
      ga('create','#{ua_code}','auto');ga('set', 'anonymizeIp', true);ga('send','pageview');
      """
      |> raw

    content_tag(:script, content)
  end

  @doc """
  Truncate `text` to `length`

      iex> truncate(nil, 5)
      ""

      iex> truncate("bork bork bork", 4)
      "bork ..."

      iex> truncate("bork bork bork", 200)
      "bork bork bork"
  """
  def truncate(nil, _), do: ""

  def truncate(text, len) when is_binary(text),
    do: (String.length(text) <= len && text) || String.slice(text, 0..len) <> "..."

  def truncate(val, _), do: val

  @doc """
  Truncate for META description

  Useful for `meta_schema`

      iex> truncate_meta_description("bork bork bork")
      "bork bork bork"

  """
  def truncate_meta_description(val), do: truncate(val, 155)

  @doc """
  Truncate for META title

  Useful for `meta_schema`

      iex> truncate_meta_title("bork bork bork")
      "bork bork bork"
  """
  def truncate_meta_title(val), do: truncate(val, 60)

  @doc """
  Renders opening body tag.

  Checks conn.private for various settings
  """
  def body_tag(conn, opts \\ []) do
    attrs = []
    id = Keyword.get(opts, :id, nil)
    data_script = conn.private[:brando_section_name]
    classes = conn.private[:brando_css_classes]

    attrs = attrs ++ [class: (classes && "#{classes} unloaded") || "unloaded"]
    attrs = (id && attrs ++ [id: id]) || attrs
    attrs = (data_script && attrs ++ [data_script: data_script]) || attrs
    attrs = attrs ++ [data_vsn: Application.spec(Brando.otp_app(), :vsn)]

    if Application.get_env(Brando.otp_app(), :show_breakpoint_debug) do
      [
        tag(:body, attrs),
        breakpoint_debug_tag(),
        grid_debug_tag()
      ]
    else
      tag(:body, attrs)
    end
  end

  def breakpoint_debug_tag do
    breakpoint = content_tag(:div, "", class: "breakpoint")

    branding =
      case(Application.get_env(:brando, :agency_brand)) do
        nil -> ""
        svg -> content_tag(:div, raw(svg), class: "brand")
      end

    user_agent = content_tag(:div, "", class: "user-agent")

    content_tag(:i, [branding, breakpoint, user_agent], class: "dbg-breakpoints")
  end

  def grid_debug_tag do
    content_tag :div, class: "dbg-grid" do
      Enum.map(1..24, fn _ -> content_tag(:b, "") end)
    end
  end

  @doc """
  Replaces all newlines with HTML break elements.
  """
  def nl2br(text), do: String.replace(text, "\n", "<br>")

  @doc """
  Calculate image ratio

      iex> ratio(%{height: nil, width: 200})
      0

      iex> ratio(%{height: 1000, width: 500})
      #Decimal<200>

      iex> ratio(nil)
      0
  """
  def ratio(%{height: height, width: width})
      when is_nil(height) or is_nil(width),
      do: 0

  def ratio(%{height: height, width: width}) do
    Decimal.new(height)
    |> Decimal.div(Decimal.new(width))
    |> Decimal.mult(Decimal.new(100))
  end

  def ratio(nil), do: 0

  @doc """
  Include CSS link tag.

  Also includes a preconnect link tag for faster resolution
  """
  @spec include_css(conn) :: safe_string | [safe_string]
  def include_css(%Plug.Conn{host: host, scheme: scheme}) do
    cdn? = !!Brando.endpoint().config(:static_url)
    hmr? = Application.get_env(Brando.otp_app(), :hmr)

    url =
      if hmr? do
        "#{scheme}://#{host}:9999/css/app.css"
      else
        (cdn? && Brando.helpers().static_url(Brando.endpoint(), "/css/app.css")) ||
          Brando.helpers().static_path(Brando.endpoint(), "/css/app.css")
      end

    css_tag = tag(:link, rel: "stylesheet", href: url, crossorigin: cdn?)

    (cdn? &&
       [
         (hmr? && []) || preconnect_tag(),
         css_tag
       ]) || css_tag
  end

  @doc """
  Renders JS script tags

  Also includes a polyfill for Safari in prod.
  """
  @spec include_js(conn) :: safe_string | [safe_string]
  def include_js(%Plug.Conn{host: host, scheme: scheme}) do
    cdn? = !!Brando.endpoint().config(:static_url)
    # check if we're HMR
    if Application.get_env(Brando.otp_app(), :hmr) do
      url = "#{scheme}://#{host}:9999/js/app.js"
      content_tag(:script, "", defer: true, src: url)
    else
      {modern_route, legacy_route} =
        case cdn? do
          true ->
            {
              Brando.helpers().static_url(
                Brando.endpoint(),
                "/js/app.js"
              ),
              Brando.helpers().static_url(
                Brando.endpoint(),
                "/js/app.legacy.js"
              )
            }

          false ->
            {
              Brando.helpers().static_path(
                Brando.endpoint(),
                "/js/app.js"
              ),
              Brando.helpers().static_path(
                Brando.endpoint(),
                "/js/app.legacy.js"
              )
            }
        end

      polyfill =
        '''
        !function(e,t,n){!("noModule"in(t=e.createElement("script")))&&"onbeforeload"in t&&(n=!1,e.addEventListener("beforeload",function(e){if(e.target===t)n=!0;else if(!e.target.hasAttribute("nomodule")||!n)return;e.preventDefault()},!0),t.type="module",t.src=".",e.head.appendChild(t),t.remove())}(document)
        '''
        |> Phoenix.HTML.raw()

      [
        content_tag(:script, polyfill, type: "module"),
        content_tag(:script, "",
          defer: true,
          src: modern_route,
          type: "module",
          crossorigin: cdn?
        ),
        content_tag(:script, "",
          defer: true,
          src: legacy_route,
          nomodule: true,
          crossorigin: cdn?
        )
      ]
    end
  end

  @doc """
  Run JS init code
  """
  @spec init_js() :: safe_string
  def init_js() do
    js =
      "(function(C){C.remove('no-js');C.add('js');C.add('moonwalk')})(document.documentElement.classList)"

    :script
    |> content_tag(raw(js))
    |> raw
  end

  @doc """
  Renders a link tag with preconnect to the CDN domain
  """
  @spec preconnect_tag :: safe_string
  def preconnect_tag do
    static_url = Brando.endpoint().static_url
    tag(:link, href: static_url, rel: "preconnect", crossorigin: true)
  end

  @doc """
  Render rel links
  """
  @spec render_rel(conn) :: [safe_string]
  def render_rel(_), do: []
end
