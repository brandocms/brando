defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  @type alert_levels :: :default | :primary | :info | :success | :warning | :danger
  @type safe_string :: {:safe, [...]}
  @type conn :: Plug.Conn.t()

  alias Brando.Utils

  use Phoenix.Component
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
  defdelegate video_tag(src), to: Brando.HTML.Video
  defdelegate video_tag(src, opts), to: Brando.HTML.Video

  @doc """
  Link preload fonts

  ## Example

      preload_fonts([{:woff2, "/fonts/my-font.woff2"}])

  """
  def preload_fonts([]), do: []

  def preload_fonts(fonts) when is_list(fonts) do
    Enum.map(
      fonts,
      fn {type, font} ->
        tag(:link,
          rel: "preload",
          href: font,
          as: "font",
          type: "font/#{type}",
          crossorigin: true
        )
      end
    )
  end

  def render_palettes_css do
    """
    <style>
    #{Brando.Cache.Palettes.get()}
    </style>
    """
    |> raw
  end

  @doc """
  Replace $csrftoken in `html` with .. csrf token!

  This is useful for rendered forms from Villain that needs a token for submission
  """
  def replace_csrf_token(html) when is_binary(html),
    do: String.replace(html, "$csrftoken", Plug.CSRFProtection.get_csrf_token())

  def replace_timestamp(html) when is_binary(html) do
    timestamp =
      DateTime.utc_now()
      |> DateTime.to_unix()
      |> to_string()

    String.replace(html, "$timestamp", timestamp)
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
  @spec zero_pad(val :: binary | integer, count :: integer) :: binary
  def zero_pad(str, count \\ 3)
  def zero_pad(val, count) when is_binary(val), do: String.pad_leading(val, count, "0")

  def zero_pad(val, count) when is_integer(val),
    do: String.pad_leading(Integer.to_string(val), count, "0")

  @doc """
  Split `name` and return first name
  """
  def first_name(name) do
    name
    |> String.split()
    |> hd()
  end

  @doc """
  Displays a banner informing about cookie laws

  ## Example

      <.cookie_law button_text="Fine">
        This website uses cookies
      </.cookie_law>
  """
  def cookie_law(assigns) do
    assigns =
      assigns
      |> assign_new(:button_text, fn -> "OK" end)
      |> assign_new(:info_link, fn -> "/cookies" end)
      |> assign_new(:info_text, fn -> "More info" end)

    ~H"""
    <div class="container cookie-container">
      <div class="cookie-container-inner">
        <div class="cookie-law">
          <div class="cookie-law-text">
            <p><%= render_slot(@inner_block) %></p>
          </div>
          <div class="cookie-law-buttons">
            <button class="dismiss-cookielaw">
              <%= @button_text %>
            </button>
            <%= if @info_text do %>
              <a href={@info_link} class="info-cookielaw">
                <%= @info_text %>
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
  @spec google_analytics(ua_code :: binary) :: safe_string()
  def google_analytics(ua_code) do
    content =
      """
      (function(b,o,i,l,e,r){b.GoogleAnalyticsObject=l;b[l]||(b[l]=
      function(){(b[l].q=b[l].q||[]).push(arguments)});b[l].l=+new Date;
      e=o.createElement(i);r=o.getElementsByTagName(i)[0];
      e.src='https://www.google-analytics.com/analytics.js';
      r.parentNode.insertBefore(e,r)}(window,document,'script','ga'));
      ga('create','#{ua_code}','auto');ga('set','anonymizeIp',true);ga('send','pageview');
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
  def body_tag(%{conn: conn, id: id} = assigns) do
    data_script = conn.private[:brando_section_name]
    classes = conn.private[:brando_css_classes]
    data_vsn = Application.spec(Brando.otp_app(), :vsn)
    show_breakpoint_debug? = Application.get_env(Brando.otp_app(), :show_breakpoint_debug)

    ~H"""
    <body id={id} class={[classes, "unloaded"]} data-script={data_script} data-vsn={data_vsn}>
      <%= if show_breakpoint_debug? do %>
        <.breakpoint_debug_tag />
        <.grid_debug_tag />
      <% end %>
      <%= render_block(@inner_block) %>
    </body>
    """
  end

  def breakpoint_debug_tag(assigns) do
    agency_brand = Application.get_env(:brando, :agency_brand)

    ~H"""
    <i class="dbg-breakpoints">
      <%= if agency_brand do %><div class="brand"><%= raw(agency_brand) %></div><% end %>
      <div class="breakpoint"></div>
      <div class="user-agent"></div>
    </i>
    """
  end

  def grid_debug_tag(assigns) do
    ~H"""
    <div class="dbg-grid">
      <%= for _ <- 1..24 do %><b></b><% end %>
    </div>
    """
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
  Inject critical css
  """
  def inject_critical_css() do
    "<style>#{Brando.Assets.Vite.Manifest.critical_css()}</style>" |> raw()
  end

  @doc """
  If you use Vite assets pipeline
  """
  def include_assets do
    if Brando.env() == :prod do
      ~E|<%= Brando.Assets.Vite.Render.main_css() %>
    <%= Brando.Assets.Vite.Render.main_js() %>|
    else
      if Application.get_env(Brando.otp_app(), :hmr) === false do
        ~E|<%= Brando.Assets.Vite.Render.main_css() %>
        <%= Brando.Assets.Vite.Render.main_js() %>|
      else
        ~E|<!-- dev/test -->
        <script type="module" src="http://localhost:3000/@vite/client"></script>
        <script type="module" src="http://localhost:3000/js/critical.js"></script>
        <script type="module" src="http://localhost:3000/js/index.js"></script>
        <!-- end dev/test -->|
      end
    end
  end

  @doc """
  Include legacy bundles

  Call this right before your closing `</body>` tag.
  """
  def include_legacy_assets,
    do: (Brando.env() == :prod && Brando.Assets.Vite.Render.legacy_js()) || []

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

  def absolute_url(%{__struct__: module} = entry) do
    module.__absolute_url__(entry)
  end

  def render_classes(list) do
    Enum.reduce(list, [], fn
      {c, cd}, acc ->
        if cd do
          acc ++ (c |> to_string() |> List.wrap())
        else
          acc
        end

      c, acc ->
        acc ++ (c |> to_string() |> List.wrap())
    end)
    |> Enum.join(" ")
  end
end
