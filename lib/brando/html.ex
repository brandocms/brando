defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  @type alert_levels :: :default | :primary | :info | :success | :warning | :danger
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

  @doc """
  Returns `active` if `conn`'s `full_path` matches `current_path`.
  """
  @spec active(conn, String.t()) :: String.t()
  def active(conn, url_to_match, add_class? \\ nil) do
    result = (add_class? && ~s(class="active")) || "active"
    (Utils.active_path?(conn, url_to_match) && result) || ""
  end

  @doc """
  Checks if current_user in conn has `role`
  """
  @spec can_render?(conn, map) :: boolean
  def can_render?(_, %{role: nil}), do: true

  def can_render?(conn, %{role: role}) do
    current_user = Utils.current_user(conn)

    if current_user do
      (role in Utils.current_user(conn).role && true) || false
    else
      false
    end
  end

  def can_render?(_, _), do: true

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
  def cookie_law(conn, text, opts \\ []) do
    if Map.get(conn.cookies, "cookielaw_accepted") != "1" do
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
  end

  @doc """
  Output Google Analytics code for `code`

  ## Example

      google_analytics("UA-XXXXX-X")

  """
  @spec google_analytics(ua_code :: String.t()) :: {:safe, term}
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
  """
  def truncate(nil, _), do: ""

  def truncate(text, len) when is_binary(text),
    do: (String.length(text) <= len && text) || String.slice(text, 0..len) <> "..."

  def truncate(val, _), do: val

  def truncate_meta_description(val), do: truncate(val, 155)
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

  defp breakpoint_debug_tag do
    breakpoint = content_tag(:div, "", class: "breakpoint")

    branding =
      case(Application.get_env(:brando, :agency_brand)) do
        nil -> ""
        svg -> content_tag(:div, raw(svg), class: "brand")
      end

    user_agent = content_tag(:div, "", class: "user-agent")

    content_tag(:i, [branding, breakpoint, user_agent], class: "dbg-breakpoints")
  end

  defp grid_debug_tag do
    content_tag :div, class: "dbg-grid" do
      [
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, ""),
        content_tag(:b, "")
      ]
    end
  end

  @doc """
  Displays all flash messages in conn
  """
  def display_flash(conn) do
    flash = Phoenix.Controller.get_flash(conn)

    for {type, msg} <- flash do
      """
      <div class="alert alert-block alert-#{type}">
        <a class="close pull-right" data-dismiss="alert" href="#">×</a>
        <i class="fa fa-exclamation-circle m-r-sm"> </i>
        #{msg}
      </div>
      """
      |> raw()
    end
  end

  @doc """
  Replaces all newlines with HTML break elements.
  """
  def nl2br(text), do: String.replace(text, "\n", "<br>")

  @doc """
  Calculate image ratio
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
  @spec include_css :: {:safe, [...]} | [{:safe, [...]}]
  @spec include_css(conn) :: {:safe, [...]} | [{:safe, [...]}]
  def include_css, do: do_include_css(Brando.endpoint().host)
  def include_css(conn), do: do_include_css(conn.host)

  def do_include_css(host) do
    cdn? = !!Brando.endpoint().config(:static_url)
    hmr? = Application.get_env(Brando.otp_app(), :hmr)

    url =
      if hmr? do
        "http://#{host}:9999/css/app.css"
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
  @spec include_js() :: [{:safe, [...]}]
  @spec include_js(conn) :: [{:safe, [...]}]
  def include_js, do: do_include_js(Brando.endpoint().host)
  def include_js(conn), do: do_include_js(conn.host)

  defp do_include_js(host) do
    cdn? = !!Brando.endpoint().config(:static_url)
    # check if we're HMR
    if Application.get_env(Brando.otp_app(), :hmr) do
      url = "http://#{host}:9999/js/app.js"
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
  Renders a link tag with preconnect to the CDN domain
  """
  @spec preconnect_tag :: {:safe, [...]}
  def preconnect_tag do
    static_url = Brando.endpoint().static_url
    tag(:link, href: static_url, rel: "preconnect", crossorigin: true)
  end

  @doc """
  Render rel links
  """
  @spec render_rel(conn) :: [{:safe, term}]
  def render_rel(_), do: []
end
