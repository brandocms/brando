defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  import Phoenix.HTML

  alias Brando.Assets.Vite
  alias Brando.Blueprint.URL
  alias Brando.Utils

  @type alert_levels :: :default | :primary | :info | :success | :warning | :danger
  @type safe_string :: {:safe, [...]}
  @type conn :: Plug.Conn.t()

  defdelegate meta_tag(tuple), to: Brando.Meta.HTML
  defdelegate picture(assigns), to: Brando.HTML.Images
  defdelegate render_json_ld(assigns), to: Brando.JSONLD.HTML
  defdelegate render_meta(assigns), to: Brando.Meta.HTML
  defdelegate video(assigns), to: Brando.HTML.Video

  # TODO: Drop before 1.0
  @deprecated "Use heex component `<.picture src={src} opts={opts} />` instead"
  def picture_tag(src, opts \\ []) do
    assigns = %{src: src, opts: opts}

    ~H"""
    <Brando.HTML.Images.picture src={@src} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
    |> raw()
  end

  # TODO: Drop before 1.0
  @deprecated "Use heex component `<.video video={src} opts={opts} />` instead"
  def video_tag(video, opts) do
    assigns = %{video: video, opts: opts}

    ~H"""
    <Brando.HTML.Video.video video={@video} opts={@opts} />
    """
    |> Phoenix.LiveViewTest.rendered_to_string()
    |> raw()
  end

  attr :menu, :map, required: true
  attr :statuses, :list, default: [:published]
  slot :inner_block, required: true

  def menu(assigns) do
    ~H"""
    <%= for item <- @menu.items do %>
      <%= if Enum.member?(@statuses, item.status) do %>
        {render_slot(@inner_block, item)}
      <% end %>
    <% end %>
    """
  end

  attr :item, :map, required: true
  attr :conn, Plug.Conn, required: true
  attr :class, :any, default: nil
  attr :splat, :boolean, default: true
  slot :inner_block

  def menu_item(assigns) do
    item = assigns.item

    url = get_menu_item_url(item) || ""
    text = get_menu_item_text(item)
    target_blank? = get_menu_item_target_blank(item)
    key = item.key

    front_page_url? = front_page_url?(url)
    splat_url? = (assigns.splat && !front_page_url? && String.starts_with?(url, "/")) || false
    match_url = (splat_url? && Path.join([url, "*"])) || url

    active? =
      if front_page_url?,
        do: on_front_page?(assigns.conn, url),
        else: Utils.active_path?(assigns.conn, match_url)

    # drop the leading slash if the url is a hash link and we are on the root path
    url =
      if String.starts_with?(url, "/#") and assigns.conn.request_path == "/" do
        String.slice(url, 1, String.length(url))
      else
        url
      end

    assigns =
      assigns
      |> assign(:url, url)
      |> assign(:text, text)
      |> assign(:key, key)
      |> assign(:active, active?)
      |> assign(:target_blank?, target_blank?)

    ~H"""
    <a class={@class} data-link-active={@active} data-menu-item-key={@key} href={@url} target={@target_blank? && "_blank"}>
      {render_slot(@inner_block, @text)}
    </a>
    """
  end

  # A front page link (`/`, `/no`, `/no/`) matches only that front page:
  # splatted, it would match every page in the language
  defp front_page_url?(url) do
    case String.trim_trailing(url, "/") do
      "" -> url == "/"
      "/" <> language -> language in language_codes()
      _ -> false
    end
  end

  defp language_codes do
    :languages
    |> Brando.config()
    |> List.flatten()
    |> Keyword.get_values(:value)
    |> Enum.map(&to_string/1)
  end

  # The locale plug's `force_path` puts the language in front of `path_info`,
  # so `GET /` reads as `/en` there. The request path keeps the URL as visited.
  defp on_front_page?(conn, url) do
    url = String.trim_trailing(url, "/")

    [conn.request_path, Path.join(["/" | conn.path_info])]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.any?(&(String.trim_trailing(&1, "/") == url))
  end

  attr :item, :map, required: true
  attr :type, :atom, default: :button
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to button"
  slot :inner_block

  def menu_button(assigns) do
    item = assigns.item
    text = get_menu_item_text(item)
    key = item.key

    assigns =
      assigns
      |> assign(:text, text)
      |> assign(:key, key)

    ~H"""
    <button data-menu-item-key={@key} type={@type} {@rest}>
      {render_slot(@inner_block, @text)}
    </button>
    """
  end

  def menu_item_url(assigns) do
    item = assigns.item
    url = get_menu_item_url(item) || ""
    assigns = assign(assigns, :url, url)

    ~H"""
    {@url}
    """
  end

  def menu_item_text(assigns) do
    item = assigns.item
    text = get_menu_item_text(item) || ""
    assigns = assign(assigns, :text, text)

    ~H"""
    {@text}
    """
  end

  def get_menu_item_url(%{link: %{link_type: :url, value: url}}), do: url

  def get_menu_item_url(%{link: %{link_type: :identifier, identifier: %{} = identifier}}),
    do: Brando.Content.Identifier.link_url(identifier)

  def get_menu_item_url(_), do: nil

  def get_menu_item_text(%{link: %{link_type: :url, link_text: text}}), do: text

  def get_menu_item_text(%{link: %{link_type: :identifier, link_text: text}}) when not is_nil(text), do: text

  def get_menu_item_text(%{link: %{link_type: :identifier, link_text: nil, identifier: %{title: text}}}), do: text

  def get_menu_item_text(_), do: nil

  def get_menu_item_target_blank(%{link: %{link_target_blank: true}}), do: true
  def get_menu_item_target_blank(_), do: false

  @doc """
  Renders a [Lucide](https://lucide.dev/icons) icon. See `Brando.HTML.Icon.icon/1`.

  ## Examples

      <.icon name="x" />
      <.icon name="refresh-cw" class="animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  def icon(assigns), do: Brando.HTML.Icon.icon(assigns)

  @doc """
  Outputs an alternate URL for the current URL in conn

  ## Example

      <.alternate_url
        :for={lang <- @available_languages}
        conn={@conn}
        language={lang}
        class={["language-switch", lang == @language && "active"])
        fallback="/">
        {{ lang }}
      </.alternate_url>
  """
  attr :conn, :map
  attr :class, :any, default: nil
  attr :language, :any
  attr :fallback, :string, default: "/"
  attr :rest, :global
  slot :inner_block

  def alternate_url(assigns) do
    href = get_alternate_url(assigns)

    assigns = assign(assigns, :href, href)

    ~H"""
    <a href={@href} class={@class} {@rest}>{render_slot(@inner_block)}</a>
    """
  end

  defp get_alternate_url(%{fallback: fallback, language: language, conn: %{private: %{brando_hreflangs: hreflangs}}}) do
    Keyword.get(hreflangs, language, fallback)
  end

  defp get_alternate_url(assigns), do: assigns.fallback

  @doc """
  Link preload fonts

  ## Example

      <.preload_fonts fonts={[
        {:woff2, "/fonts/my-font.woff2?vsn=d"}
      ]} />

  """
  attr :fonts, :list, default: []

  def preload_fonts(assigns) do
    ~H"""
    <link
      :for={{type, font} <- @fonts}
      :key={font}
      rel="preload"
      href={Brando.endpoint().static_path(font)}
      as="font"
      type={"font/#{type}"}
      crossorigin={true}
    />
    """
  end

  attr :fragment, Brando.Pages.Fragment
  attr :parent_key, :string
  attr :key, :string
  attr :language, :string

  # An unpublished fragment renders nothing, as with `Brando.Pages.render_fragment/1`.
  def fragment(%{fragment: fragment} = assigns) when not is_nil(fragment) do
    assigns = assign(assigns, :html, Brando.Pages.render_fragment(fragment))

    ~H"""
    {@html}
    """
  end

  # A key missing from a partials map.
  def fragment(%{fragment: nil} = assigns) when not is_map_key(assigns, :parent_key), do: ~H""

  # `render_fragment/3` returns safe HTML (or a missing-fragment notice), not
  # the fragment itself.
  def fragment(assigns) do
    assigns =
      assign(
        assigns,
        :html,
        Brando.Pages.render_fragment(assigns.parent_key, assigns.key, assigns.language)
      )

    ~H"""
    {@html}
    """
  end

  def render_hreflangs(%{conn: %{private: %{brando_hreflangs: hreflangs}}} = assigns) do
    canonical =
      Brando.Plug.HTML.get_canonical(assigns.conn) ||
        hreflangs
        |> List.first()
        |> elem(1)

    assigns =
      assigns
      |> assign(:canonical, canonical)
      |> assign(:hreflangs, hreflangs)
      |> assign(:multilang, Enum.count(hreflangs) > 1)

    assigns = assign(assigns, :markdown_url, markdown_alternate(assigns.conn))

    ~H"""
    <link rel="canonical" href={@canonical} />
    <link
      :for={{lang, url} <- @hreflangs}
      :if={@multilang}
      :key={lang}
      rel="alternate"
      href={url}
      type="text/html"
      hreflang={lang}
    />
    <link :if={@markdown_url} rel="alternate" type="text/markdown" href={@markdown_url} />
    """
  end

  def render_hreflangs(assigns) do
    canonical = Brando.Plug.HTML.get_canonical(assigns.conn) || Brando.Utils.current_url(assigns.conn)

    assigns =
      assigns
      |> assign(:canonical, canonical)
      |> assign(:markdown_url, markdown_alternate(assigns.conn))

    ~H"""
    <link rel="canonical" href={@canonical} />
    <link :if={@markdown_url} rel="alternate" type="text/markdown" href={@markdown_url} />
    """
  end

  # The page's Markdown version (`Brando.SEO.Markdown`), when its entry has one.
  defp markdown_alternate(conn) do
    entry = Brando.Plug.HTML.get_page_entry(conn)
    if Brando.SEO.Markdown.available?(entry), do: Brando.SEO.Markdown.url(entry)
  end

  @doc """
  Fills in `$csrftoken` in rendered block HTML with the visitor's CSRF token.

  Pages, fragments and `render_blocks/1` already do this; call it for block
  HTML output any other way. See `Brando.Forms.Delivery.finalize/1`.
  """
  def replace_csrf_token(html), do: Brando.Forms.Delivery.finalize(html)

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
  @spec active(conn | binary, binary) :: binary
  def active(source, url_to_match, add_class? \\ nil) do
    result = (add_class? && ~s(class="active")) || "active"
    (Utils.active_path?(source, url_to_match) && result) || ""
  end

  @doc """
  Render markdown as html raw
  """
  def render_markdown(markdown, opts \\ [breaks: true])
  def render_markdown(nil, _), do: ""
  def render_markdown(markdown, opts), do: markdown |> Brando.Markdown.to_html!(opts) |> raw()

  @doc """
  Zero pad `val` as a binary.

  ## Example

      iex> zero_pad(5)
      "005"

  """
  @spec zero_pad(binary | integer, non_neg_integer) :: binary
  def zero_pad(str, count \\ 3)
  def zero_pad(val, count) when is_binary(val), do: String.pad_leading(val, count, "0")

  def zero_pad(val, count) when is_integer(val), do: String.pad_leading(Integer.to_string(val), count, "0")

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
      |> assign_new(:button_text, fn -> gettext("OK") end)
      |> assign_new(:info_link, fn -> gettext("/cookies") end)
      |> assign_new(:info_text, fn -> gettext("More info") end)

    ~H"""
    <div class="container cookie-container">
      <div class="cookie-container-inner">
        <div class="cookie-law">
          <div class="cookie-law-text">
            <p>{render_slot(@inner_block)}</p>
          </div>
          <div class="cookie-law-buttons">
            <button class="dismiss-cookielaw">
              {@button_text}
            </button>
            <%= if @info_text do %>
              <a href={@info_link} class="info-cookielaw">
                {@info_text}
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

      <.google_analytics code="..." />

  """
  attr :code, :string, required: true

  def google_analytics(assigns) do
    ~H"""
    <script>
      (function(b,o,i,l,e,r){b.GoogleAnalyticsObject=l;b[l]||(b[l]=
      function(){(b[l].q=b[l].q||[]).push(arguments)});b[l].l=+new Date;
      e=o.createElement(i);r=o.getElementsByTagName(i)[0];
      e.src='https://www.google-analytics.com/analytics.js';
      r.parentNode.insertBefore(e,r)}(window,document,'script','ga'));
      ga('create','<%= @code %>','auto');ga('set','anonymizeIp',true);ga('send','pageview');
    </script>
    """
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
    extra = assigns_to_attributes(assigns, [:id, :conn])

    assigns =
      assigns
      |> assign(:id, id)
      |> assign(:classes, classes)
      |> assign(:data_script, data_script)
      |> assign(:data_vsn, data_vsn)
      |> assign(:show_breakpoint_debug?, show_breakpoint_debug?)
      |> assign(:extra, extra)

    ~H"""
    <body id={@id} class={[@classes, "unloaded"]} data-script={@data_script} data-vsn={@data_vsn} {@extra}>
      <%= if @show_breakpoint_debug? do %>
        <.breakpoint_debug_tag />
        <.grid_debug_tag />
      <% end %>
      {render_slot(@inner_block)}
    </body>
    """
  end

  def breakpoint_debug_tag(assigns) do
    assigns = assign(assigns, :agency_brand, Application.get_env(:brando, :agency_brand))

    ~H"""
    <i class="dbg-breakpoints">
      <%= if @agency_brand do %>
        <div class="brand">{raw(@agency_brand)}</div>
      <% end %>
      <div class="breakpoint"></div>
      <div class="user-agent"></div>
    </i>
    """
  end

  def grid_debug_tag(assigns) do
    ~H"""
    <div class="dbg-grid">
      <%= for _ <- 1..24 do %>
        <b></b>
      <% end %>
    </div>
    """
  end

  @doc """
  An alert component
  """
  attr :type, :atom, default: :info
  slot :icon
  slot :close
  slot :inner_block, required: true

  def alert(assigns) do
    ~H"""
    <div class={["alert", @type]}>
      <div class="icon">
        {render_slot(@icon)}
      </div>
      <div class="content">
        {render_slot(@inner_block)}
      </div>
      <div class="close">
        {render_slot(@close)}
      </div>
    </div>
    """
  end

  @doc """
  Replaces all newlines with HTML break elements.
  """
  def nl2br(text), do: String.replace(text, "\n", "<br>")

  @doc """
  Calculate image ratio, as a percentage rounded to four decimal places.

  Non-terminating divisions are rounded rather than carried to the full
  precision of the current `Decimal.Context`, which would emit dozens of
  digits into markup for no visual difference.

      iex> ratio(%{height: nil, width: 200})
      0

      iex> ratio(%{height: 1000, width: 500})
      Decimal.new(\"200.0000\")

      iex> ratio(%{height: 1000, width: 300})
      Decimal.new(\"333.3333\")

      iex> ratio(nil)
      0
  """
  def ratio(%{height: height, width: width}) when is_nil(height) or is_nil(width), do: 0

  def ratio(%{height: height, width: width}) do
    height
    |> Decimal.new()
    |> Decimal.div(Decimal.new(width))
    |> Decimal.mult(Decimal.new(100))
    |> Decimal.round(4)
  end

  def ratio(nil), do: 0

  @doc """
  Inject critical css
  """
  def inject_critical_css(assigns) do
    ~H|<style>
  <%= Vite.Manifest.critical_css() %>
</style>|
  end

  attr :conn, :map, required: true
  attr :charset, :string, default: "utf-8"
  attr :viewport, :string, default: "width=device-width, initial-scale=1"
  attr :fonts, :list, default: []
  attr :ignored_chunks, :list, default: []
  slot :pragma
  slot :title
  slot :preconnect
  slot :async_scripts
  slot :import_styles
  slot :scripts
  slot :styles
  slot :preload
  slot :deferred_scripts
  slot :prefetch
  slot :inner_block

  def head(assigns) do
    # Once for the page: the record can change between the styles and the scripts
    assigns = assign(assigns, :assets_source, site_assets_source())

    ~H"""
    <head phx-no-format>
      <meta charset={@charset} />
      <meta name="viewport" content={@viewport} />
      <%= if @pragma != [] do %><%= render_slot(@pragma) %><% end %>
      <%= if @title != [] do %><title><%= render_slot(@title) %></title><% else %><title><%= Brando.Utils.get_page_title(@conn) %></title><% end %>
      <%= if @preconnect != [] do %><%= render_slot(@preconnect) %><% end %>
      <%= if @async_scripts != [] do %><%= render_slot(@async_scripts) %><% end %>
      <.init_js />
      <%= if @import_styles != [] do %><%= render_slot(@import_styles) %><% end %>
      <%= if @scripts != [] do %><%= render_slot(@scripts) %><% end %>
      <.inject_critical_css />
      <.site_css source={@assets_source} />
      <.render_palettes_css />
      <%= if @styles != [] do %><%= render_slot(@styles) %><% end %>
      <.preload_fonts fonts={@fonts} />
      <%= if @preload != [] do %><%= render_slot(@preload) %><% end %>
      <.site_js source={@assets_source} ignored_chunks={@ignored_chunks} />
      <%= if @deferred_scripts != [] do %><%= render_slot(@deferred_scripts) %><% end %>
      <%= if @prefetch != [] do %><%= render_slot(@prefetch) %><% end %>

      <.render_meta conn={@conn} />
      <.render_rel conn={@conn} />
      <.render_json_ld conn={@conn} />
      <.render_hreflangs conn={@conn} />

      <%= render_slot(@inner_block) %>
    </head>
    """
  end

  @doc """
  Includes assets from the Vite pipeline.

  During development with HMR enabled, the dev-server origins use these
  environment variables:

  | Variable | Default |
  | --- | --- |
  | `BRANDO_VITE_FRONTEND_HOST` | `localhost` |
  | `BRANDO_VITE_FRONTEND_PORT` | `3000` |
  | `BRANDO_VITE_ADMIN_HOST` | `localhost` |
  | `BRANDO_VITE_ADMIN_PORT` | `3333` |

  Hosts are hostnames or IP addresses, without a scheme or port. Dev servers
  use HTTP. Export the variables in each project's shell environment (for
  example, `.envrc`) so both Phoenix and Vite inherit them:

      export BRANDO_VITE_FRONTEND_PORT=3001
      export BRANDO_VITE_ADMIN_PORT=3334

  The installer Vite configs read the same variables, with `strictPort`, so a
  taken port stops Vite instead of moving it to a port Phoenix does not know.
  Existing applications should copy the corresponding `server` settings into
  their Vite configs. A Vite-only `.env` file does not configure the Phoenix
  process. `mix brando.install` starts both dev servers from the endpoint's
  `watchers` in `config/dev.exs`, through `Brando.Vite`. In development, the
  page shows a notice when a dev server's scripts fail to load. When a
  `Brando.Vite` watcher could not start its Vite (`Brando.Vite.start_failure/1`),
  for example because another site's Vite holds the port, the admin or the
  site renders its manifest assets instead, with a notice saying why.

  These values are read at render time, rather than through application config,
  because they only configure development servers and must agree with Vite's
  process environment without recompiling. Disable HMR as before with
  `config :your_app, hmr: false`, using the host application's OTP app. Manifest
  rendering does not read these variables.
  """
  attr :only_js, :boolean, default: false
  attr :only_css, :boolean, default: false
  attr :admin, :boolean, default: false
  attr :ignored_chunks, :list, default: []

  def include_assets(%{admin: true} = assigns) do
    case admin_assets_source() do
      :manifest ->
        assigns = assign(assigns, :unbuilt?, Brando.env() == :dev and manifest_empty?(:admin))

        ~H"""
        {Vite.Render.main_css(:admin) |> raw()}
        {Vite.Render.main_js(:admin) |> raw()}
        <.assets_notice :if={@unbuilt?} scope={:admin} show />
        """

      {:vite_failed, failure} ->
        assigns = vite_failed_assigns(assigns, :admin, failure)

        ~H"""
        {Vite.Render.main_css(:admin) |> raw()}
        {Vite.Render.main_js(:admin) |> raw()}
        <.assets_notice :if={@notice?} scope={:admin} failure={@failure} unbuilt={@unbuilt?} show />
        """

      :dev_server ->
        assigns =
          assign(assigns,
            vite_origin: vite_dev_server_origin("ADMIN", 3333),
            notice?: Brando.env() == :dev
          )

        ~H"""
        <!-- admin dev/test -->
        <.assets_notice :if={@notice?} scope={:admin} origin={@vite_origin} />
        <script
          type="module"
          src={@vite_origin <> "/@vite/client"}
          onerror={@notice? && "brandoAssetsMissing('brando-admin-assets-notice')"}
          phx-no-format
        >
        </script>
        <script
          type="module"
          src={@vite_origin <> "/src/main.js"}
          onerror={@notice? && "brandoAssetsMissing('brando-admin-assets-notice')"}
          phx-no-format
        >
        </script>
        <!-- end admin dev/test -->
        """
    end
  end

  def include_assets(%{only_css: true} = assigns),
    do: site_css(assign(assigns, :source, site_assets_source()))

  def include_assets(%{only_js: true} = assigns),
    do: site_js(assign(assigns, :source, site_assets_source()))

  def include_assets(assigns) do
    case site_assets_source() do
      :manifest ->
        ~H"""
        {Vite.Render.main_css() |> raw()}
        {Vite.Render.main_js() |> raw()}
        """

      {:vite_failed, failure} ->
        assigns = vite_failed_assigns(assigns, :site, failure)

        ~H"""
        {Vite.Render.main_css() |> raw()}
        {Vite.Render.main_js() |> raw()}
        <.assets_notice :if={@notice?} scope={:site} failure={@failure} unbuilt={@unbuilt?} show />
        """

      :dev_server ->
        ~H"""
        <.frontend_dev_scripts />
        """
    end
  end

  # The site's styles and scripts, rendered apart in the head, from one
  # decision on where the assets come from
  attr :source, :any, required: true

  defp site_css(assigns) do
    case assigns.source do
      :manifest ->
        ~H"""
        {Vite.Render.main_css() |> raw()}
        """

      {:vite_failed, failure} ->
        assigns = vite_failed_assigns(assigns, :site, failure)

        ~H"""
        {Vite.Render.main_css() |> raw()}
        <.assets_notice :if={@notice?} scope={:site} failure={@failure} unbuilt={@unbuilt?} show />
        """

      :dev_server ->
        ~H"""
        <.frontend_dev_scripts />
        """
    end
  end

  attr :source, :any, required: true
  attr :ignored_chunks, :list, default: []

  defp site_js(assigns) do
    if assigns.source == :dev_server do
      ~H"""
      <!-- prevent double loading of vite client, handled in only_css -->
      """
    else
      ~H"""
      {Vite.Render.main_js(:app, @ignored_chunks) |> raw()}
      """
    end
  end

  # Where the page loads the admin's assets from: the build in priv/static, or
  # the Vite dev server, unless this VM's Brando.Vite watcher could not start
  # it. Then the port may be another site's Vite, so the page takes the build.
  defp admin_assets_source do
    cond do
      Brando.env() in [:prod, :e2e, :test] or hmr_disabled?() -> :manifest
      failure = Brando.Vite.start_failure(:admin) -> vite_failed(:admin, failure)
      true -> :dev_server
    end
  end

  defp site_assets_source do
    cond do
      Brando.env() == :prod or Application.get_env(:brando, :ssg_run, false) -> :manifest
      hmr_disabled?() -> :manifest
      failure = Brando.Vite.start_failure(:site) -> vite_failed(:app, failure)
      true -> :dev_server
    end
  end

  # The manifest, and the site's critical CSS, are cached at their first read,
  # perhaps before the build that `pnpm build` writes while the page runs on
  # it, so development reads them afresh. `:persistent_term.put/2` with an
  # unchanged value does nothing.
  defp vite_failed(scope, failure) do
    if Brando.env() == :dev do
      Vite.Manifest.refresh(scope, keep_cached: true)
      if scope == :app, do: Vite.Manifest.refresh_critical_css()
    end

    {:vite_failed, failure}
  end

  defp hmr_disabled?, do: Application.get_env(Brando.otp_app(), :hmr) === false

  defp vite_failed_assigns(assigns, scope, failure) do
    notice? = Brando.env() == :dev

    assign(assigns,
      failure: failure,
      notice?: notice?,
      unbuilt?: notice? and manifest_empty?(if(scope == :site, do: :app, else: scope))
    )
  end

  defp frontend_dev_scripts(assigns) do
    assigns =
      assign(assigns,
        vite_origin: vite_dev_server_origin("FRONTEND", 3000),
        notice?: Brando.env() == :dev
      )

    ~H"""
    <!-- dev/test -->
    <.assets_notice :if={@notice?} scope={:site} origin={@vite_origin} />
    <script
      type="module"
      src={@vite_origin <> "/@vite/client"}
      onerror={@notice? && "brandoAssetsMissing('brando-site-assets-notice')"}
      phx-no-format
    >
    </script>
    <script
      type="module"
      src={@vite_origin <> "/js/critical.js"}
      onerror={@notice? && "brandoAssetsMissing('brando-site-assets-notice')"}
      phx-no-format
    >
    </script>
    <script
      type="module"
      src={@vite_origin <> "/js/index.js"}
      onerror={@notice? && "brandoAssetsMissing('brando-site-assets-notice')"}
      phx-no-format
    >
    </script>
    <!-- end dev/test -->
    """
  end

  defp manifest_empty?(scope) do
    Brando.Utils.try_path(Vite.Manifest.read(scope), [:entries, :files]) in [nil, []]
  end

  # Development only. Without its assets the admin, or the site, is a blank
  # page: the notice is held in a <template> in the head, and shown (with its
  # own stylesheet, the page's is what is missing) when the Vite dev server's
  # scripts fail to load (`origin`), or at once (`show`) when the admin has no
  # build or Brando.Vite could not start Vite (`failure`). It goes after
  # <body>, which the site keeps hidden until its scripts run. English, like
  # the mix tasks: it is for the developer.
  attr :scope, :atom, values: [:admin, :site], required: true
  attr :origin, :string, default: nil
  attr :failure, :map, default: nil
  attr :unbuilt, :boolean, default: false
  attr :show, :boolean, default: false

  defp assets_notice(assigns) do
    {label, name, dir, port_var, manifest} =
      case assigns.scope do
        :admin -> {"Admin", "the admin", "assets/backend", "BRANDO_VITE_ADMIN_PORT", "admin_manifest.json"}
        :site -> {"Site", "the site", "assets/frontend", "BRANDO_VITE_FRONTEND_PORT", "manifest.json"}
      end

    assigns =
      assign(assigns,
        otp_app: Brando.otp_app(),
        id: "brando-#{assigns.scope}-assets-notice",
        label: label,
        name: name,
        dir: dir,
        port_var: port_var,
        manifest: manifest
      )

    ~H"""
    <template id={@id}>
      <div class="brando-assets-notice" role="alert">
        <button
          type="button"
          class="brando-assets-notice-close"
          aria-label="Close this notice"
          onclick="this.parentNode.remove()"
        >
          &times;
        </button>
        <%= if @failure do %>
          <.vite_failure_notice failure={@failure} name={@name} port_var={@port_var} />
          <p :if={!@unbuilt}>
            This page uses the last build in <code>priv/static</code>
            instead, which does not follow your edits in <code>{@failure.dir}</code>.
          </p>
          <p :if={@unbuilt}>
            There is no build to use instead: run <code>pnpm build</code>
            in <code>{@failure.dir}</code>, then reload this page.
          </p>
        <% end %>
        <%= if !@failure && @origin do %>
          <strong>{@label} assets failed to load from {@origin}</strong>
          <p>
            Either the Vite dev server for <code>{@dir}</code>
            is not running, or it could not compile a module: check the terminal it runs in. <code>mix phx.server</code>
            starts it when the endpoint's <code>watchers</code>
            in <code>config/dev.exs</code>
            include <code>Brando.Vite</code>; otherwise run <code>pnpm dev</code>
            in <code>{@dir}</code>. Or build the assets there with <code>pnpm build</code>
            and set <code>config :{@otp_app}, hmr: false</code>.
          </p>
        <% end %>
        <%= if !@failure && !@origin do %>
          <strong>{@label} assets not built</strong>
          <p>
            There is no <code>priv/static/{@manifest}</code>. Build them with <code>pnpm build</code>
            in <code>{@dir}</code>, or set <code>config :{@otp_app}, hmr: true</code>
            to use its Vite dev server.
          </p>
        <% end %>
      </div>
    </template>
    <style>
      .brando-assets-notice{position:fixed;top:16px;left:16px;right:16px;z-index:10000;max-width:720px;margin:0 auto;padding:16px 44px 16px 20px;border:1px solid #d9a441;border-radius:8px;background:#fff8e6;color:#1d2433;font:14px/1.5 system-ui,sans-serif;box-shadow:0 4px 16px rgba(0,0,0,.08)}.brando-assets-notice p{margin:4px 0 0}.brando-assets-notice code{font:13px ui-monospace,monospace;background:rgba(0,0,0,.06);padding:1px 4px;border-radius:3px}.brando-assets-notice-close{position:absolute;top:8px;right:8px;width:28px;height:28px;padding:0;border:0;border-radius:6px;background:none;color:inherit;font:20px/28px system-ui,sans-serif;cursor:pointer}.brando-assets-notice-close:hover{background:rgba(0,0,0,.06)}.brando-assets-notice-close:focus-visible{outline:2px solid #d9a441;outline-offset:1px}
    </style>
    <script>
      window.brandoAssetsMissing=function(id){var show=function(){if(document.getElementById(id+"-shown"))return;var t=document.getElementById(id);if(!t)return;var n=t.content.firstElementChild.cloneNode(true);n.id=id+"-shown";document.documentElement.appendChild(n)};if(document.body){show()}else{document.addEventListener("DOMContentLoaded",show)}};
    </script>
    <script :if={@show}>
      brandoAssetsMissing("<%= @id %>");
    </script>
    """
  end

  attr :failure, :map, required: true
  attr :name, :string, required: true
  attr :port_var, :string, required: true

  defp vite_failure_notice(%{failure: %{reason: {:port_in_use, port}}} = assigns) do
    assigns = assign(assigns, :port, port)

    ~H"""
    <strong>Vite for {@name} did not start: port {@port} is already in use</strong>
    <p>
      Another process holds port {@port}, perhaps another site's Vite. Stop it, or give this site
      another port with <code>{@port_var}</code>, exported where both Phoenix and Vite read it
      (for example in <code>.envrc</code>), then restart <code>mix phx.server</code>.
    </p>
    """
  end

  defp vite_failure_notice(%{failure: %{reason: {:exited, status}}} = assigns) do
    assigns = assign(assigns, :status, status)

    ~H"""
    <strong>Vite for {@name} did not start</strong>
    <p>
      It exited with status {@status} before it was ready; its output is in the <code>mix phx.server</code>
      terminal. Restart <code>mix phx.server</code>
      once it is fixed.
    </p>
    """
  end

  defp vite_failure_notice(%{failure: %{reason: {:stopped, status}}} = assigns) do
    assigns = assign(assigns, :status, status)

    ~H"""
    <strong>Vite for {@name} stopped</strong>
    <p>
      It exited with status {@status}; its output is in the <code>mix phx.server</code>
      terminal. Restart <code>mix phx.server</code>
      once it is fixed.
    </p>
    """
  end

  defp vite_failure_notice(%{failure: %{reason: {:not_started, message}}} = assigns) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <strong>Vite for {@name} did not start</strong>
    <p>{@message}</p>
    """
  end

  defp vite_dev_server_origin(scope, default_port) do
    host = System.get_env("BRANDO_VITE_#{scope}_HOST", "localhost")
    port = System.get_env("BRANDO_VITE_#{scope}_PORT", to_string(default_port))

    URI.to_string(%URI{scheme: "http", host: host, port: String.to_integer(port)})
  end

  @doc """
  Include legacy bundles

  Call this right before your closing `</body>` tag.
  """
  def include_legacy_assets(assigns) do
    if Application.get_env(Brando.otp_app(), :hmr) === false do
      ~H"{Vite.Render.legacy_js() |> raw()}"
    else
      ~H||
    end
  end

  @doc """
  Run JS init code
  """
  def init_js(assigns) do
    ~H[{"<script>(function(C){C.remove('no-js');C.add('js');C.add('moonwalk')})(document.documentElement.classList)</script>"
|> raw()}]
  end

  @doc """
  Renders a link tag with preconnect to the CDN domain
  """
  def preconnect_tag(assigns) do
    assigns = assign(assigns, :static_url, Brando.endpoint().static_url)

    ~H"""
    <link href={@static_url} rel="preconnect" crossorigin="true" />
    """
  end

  @doc """
  Render rel links
  """
  def render_rel(assigns) do
    ~H||
  end

  @doc """
  Parses a villain field.

  You can also parse a "content hole", if the data field you are processing contains
  a `$__CONTENT__` delimiter. The slot goes into the first one; any later one is
  left as text.

  For instance, the template:

      something $__CONTENT__ anything

  parsed with `render_data` as such:

      <.render_data conn={@conn} entry={@entry}>
        Hello world!
      </.render_data>

  will result in

      something Hello world! anything

  """
  attr :entry, :map, required: true
  attr :block_field, :atom, default: :blocks
  attr :conn, :map, required: true
  slot :inner_block

  def render_data(assigns) do
    entry_blocks_field = :"entry_#{assigns.block_field}"

    parsed_data =
      Brando.Villain.parse(
        Map.get(assigns.entry, entry_blocks_field),
        assigns.entry,
        conn: assigns.conn
      )
      |> Brando.Forms.Delivery.finalize()

    # The first hole takes the slot; any later one stays as text, so a second
    # one in synced or pasted content cannot break the page.
    [pre, post] =
      case String.split(parsed_data, "$__CONTENT__", parts: 2) do
        [pre, post] -> [pre, post]
        [pre] -> [pre, nil]
      end

    assigns =
      assigns
      |> assign(:pre, pre)
      |> assign(:post, post)

    ~H"""
    <%= if @post do %>
      {@pre |> raw}
      {render_slot(@inner_block)}
      {@post |> raw}
    <% else %>
      {@pre |> raw}
    <% end %>
    """
  end

  attr :entry, :map, required: true
  attr :field, :atom, default: :blocks

  def render_blocks(assigns) do
    rendered_field = String.to_existing_atom("rendered_#{assigns.field}")
    rendered_field_at = String.to_existing_atom("rendered_#{assigns.field}_at")

    assigns =
      assigns
      |> assign(:rendered_field, rendered_field)
      |> assign(:rendered_field_at, rendered_field_at)
      |> assign(:html, assigns.entry |> rendered_field_html(assigns.field) |> Brando.Forms.Delivery.finalize())
      |> assign(:at, assigns.entry |> Map.get(rendered_field_at) |> inspect())

    ~H"""
    {@html |> raw}
    """
  end

  # Stored HTML, or in frontend edit mode the field rendered with block markers.
  defp rendered_field_html(entry, field), do: Brando.FrontendEdit.rendered_html(entry, field) || ""

  @doc "Render a Blueprint rich-text field with its configured footnote blocks."
  attr :entry, :map, required: true
  attr :field, :atom, required: true
  attr :title, :string, default: "Notes & sources"
  attr :scope, :string, default: nil

  def render_rich_text(assigns) do
    opts = if assigns.scope, do: [scope: assigns.scope], else: []
    result = Brando.Villain.Footnotes.render_field(assigns.entry, assigns.field, opts)

    # Editable in frontend edit mode. Notes are rendered from the field's
    # footnote blocks, so with notes the page shows the change after saving.
    kind = if result.notes == [], do: :value, else: :markup

    html =
      result
      |> Brando.Villain.Footnotes.to_html(title: assigns.title)
      |> Brando.FrontendEdit.Fields.wrap(assigns.entry, assigns.field, kind)

    assigns = assign(assigns, :html, html)

    ~H"""
    {@html |> raw}
    """
  end

  @doc """
  Prints an entry field, editable in place in frontend edit mode.

  Use it where the value shows as text on the page — not inside an
  attribute, `<title>` or a script, where markers would break the markup:

      <h1><.editable_field entry={@page} field={:title} /></h1>

  Rich-text fields print their HTML; other values are escaped. Outside edit
  mode this prints the value and nothing else. See `Brando.FrontendEdit.Fields`
  and the frontend edit guide.
  """
  attr :entry, :map, required: true
  attr :field, :atom, required: true

  def editable_field(assigns) do
    html = Brando.FrontendEdit.Fields.render_value(assigns.entry, assigns.field)
    assigns = assign(assigns, :html, Brando.FrontendEdit.Fields.wrap(html, assigns.entry, assigns.field, :value))

    ~H"""
    {raw(@html)}
    """
  end

  @doc """
  Makes an entry field editable in frontend edit mode where it is shown by
  other markup, such as an image field's picture:

      <.editable entry={@project} field={:cover}>
        <.picture src={@project.cover} opts={[…]} />
      </.editable>

  A click on it opens the field in the sidebar; the page shows the change
  after saving. Outside edit mode this renders its content and nothing else.
  """
  attr :entry, :map, required: true
  attr :field, :atom, required: true
  slot :inner_block, required: true

  def editable(assigns) do
    assigns = assign(assigns, :key, Brando.FrontendEdit.Fields.marker_key(assigns.entry, assigns.field))

    ~H"""
    <%= if @key do %>
      {raw(Brando.FrontendEdit.Fields.open(:markup, @key))}{render_slot(@inner_block)}{raw(
        Brando.FrontendEdit.Fields.close(:markup, @key)
      )}
    <% else %>
      {render_slot(@inner_block)}
    <% end %>
    """
  end

  defdelegate absolute_url(entry, mode), to: URL, as: :resolve
  defdelegate absolute_url(entry), to: URL, as: :resolve

  def render_classes(list) do
    IO.warn("render_classes/1 is deprecated. use a list of classes instead.")

    Enum.reduce(list, [], fn
      {k, v}, acc -> (v && acc ++ (k |> to_string() |> List.wrap())) || acc
      nil, acc -> acc
      k, acc -> acc ++ (k |> to_string() |> List.wrap())
    end)
  end

  def csrf_token_value, do: Plug.CSRFProtection.get_csrf_token()

  def csrf_meta_tag(assigns) do
    assigns = assign(assigns, :csrf_token, csrf_token_value())

    ~H"""
    <meta name="csrf-token" content={@csrf_token} />
    """
  end

  attr :map, :any, required: true

  @doc "Renders the best available translation from a translated map."
  def i18n(assigns), do: Brando.HTML.I18n.i18n(assigns)

  def render_palettes_css(assigns) do
    assigns = assign(assigns, :palettes_css, Brando.Cache.Palettes.get_css())

    ~H"""
    <style :if={@palettes_css != {:safe, ""}} phx-no-format><%= @palettes_css %></style>
    """
  end

  defdelegate global(lang, category, key), to: Brando.Sites, as: :render_global
  defdelegate identity(lang, key), to: Brando.Sites, as: :render_identity
end
