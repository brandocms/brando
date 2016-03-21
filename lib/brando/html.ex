defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  import Brando.Gettext
  import Brando.Utils, only: [media_url: 0, current_user: 1,
                              active_path?: 2, img_url: 3]
  import Brando.Meta.Controller, only: [put_meta: 3, get_meta: 1]
  import Phoenix.HTML.Tag, only: [content_tag: 2, content_tag: 3]

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.HTML
      import Brando.HTML.Inspect, except: [t!: 2, t: 3]
      import Brando.HTML.Tablize, except: [t!: 2, t: 3]
    end
  end

  @doc """
  Renders a menu item.
  Also calls to render submenu items, if `current_user` has required role
  """
  def render_menu_item(conn, {color, menu}) do
    submenu_items =
      menu.submenu
      |> Enum.map_join("\n", &render_submenu_item(conn, &1))

    html =
    """
    <!-- menu item -->
      <li class="menuparent">
        <a href="##{menu.anchor}">
          <i class="#{menu.icon}">
            <b style="background-color: #{color}"></b>
          </i>
          <span class="pull-right">
            <i class="fa fa-angle-down text"></i>
            <i class="fa fa-angle-up text-active"></i>
          </span>
          <span>#{menu.name}</span>
        </a>
        <ul class="nav lt">
          #{submenu_items}
        </ul>
      </li>
    <!-- /menu item -->
    """
    html |> Phoenix.HTML.raw
  end

  @doc """
  Creates a menu link from a submenu item.
  Also checks if current_user has required role.
  """
  def render_submenu_item(conn, item) do
    {fun, action} = item.url
    if can_render?(conn, item) do
      url = apply(Brando.Utils.helpers(conn), fun, [conn, action])
      active? = active_path?(conn, url)
      li_classes = active? && "menuitem active" || "menuitem"
      a_class = active? && "active" || ""
      {:safe, html} = content_tag :li, [class: li_classes] do
        content_tag :a, [href: url, class: a_class] do
          [content_tag(:i, "", [class: "fa fa-angle-right"]),
           content_tag(:span, item.name)]
        end
      end
      html
    else
      ""
    end
  end

  @doc """
  Returns `active` if `conn`'s `full_path` matches `current_path`.
  """
  @spec active(Plug.Conn.t, String.t) :: String.t
  def active(conn, url_to_match) do
    if active_path?(conn, url_to_match) do
      "active"
    else
      ""
    end
  end

  @doc """
  Checks if current_user in conn has `role`
  """
  @spec can_render?(Plug.Conn.t, Map.t) :: boolean
  def can_render?(_, %{role: nil}) do
    true
  end
  def can_render?(conn, %{role: role}) do
    role in current_user(conn).role && true || false
  end
  def can_render?(_, _) do
    true
  end

  @doc """
  Shows `content` if `current_user` has `role` that allows it.
  """
  def auth_content(conn, role, do: {:safe, block}) do
    html = can_render?(conn, %{role: role}) && block || ""
    Phoenix.HTML.raw(html)
  end

  @doc """
  Shows `link` if `current_user` has `role` that allows it.
  """
  @spec auth_link(Plug.Conn.t, String.t, atom, {:safe, String.t}) :: String.t
  def auth_link(conn, link, role, do: {:safe, block}) do
    do_auth_link({"btn-default", conn, link, role}, block)
  end
  @doc """
  Shows `link` with `type` if `current_user` has `role` that allows it.
  """
  @spec auth_link(:default | :primary | :info | :success | :warning | :danger,
                  Plug.Conn.t, String.t, atom, {:safe, String.t}) :: String.t
  def auth_link(type, conn, link, role, do: {:safe, block}) do
    do_auth_link({"btn-#{type}", conn, link, role}, block)
  end
  defp do_auth_link({class, conn, link, role}, block) do
    html =
      if can_render?(conn, %{role: role}) do
        ~s(<a href="#{link}" class="btn #{class}"> #{to_string(block)}</a>)
      else
        ""
      end
    Phoenix.HTML.raw(html)
  end

  @doc """
  Zero pad `int` as a binary.

  ## Example

      iex> zero_pad(5)
      "005"

  """
  def zero_pad(str) when is_binary(str) do
    String.rjust(str, 3, ?0)
  end
  def zero_pad(int) do
    String.rjust(Integer.to_string(int), 3, ?0)
  end

  @doc """
  Split `full_name` and return first name
  """
  def first_name(full_name) do
    full_name
    |> String.split
    |> hd
  end

  @doc """
  Renders a delete button wrapped in a POST form.
  Pass `params` instance of model (if one param), or a list of multiple
  params, and `helper` path.
  """
  @spec delete_form_button(atom, Keyword.t | %{atom => any}) :: String.t
  def delete_form_button(helper, params) do
    action = Brando.Form.apply_action(helper, :delete, params)
    html =
    """
    <form method="POST" action="#{action}">
      <input type="hidden" name="_method" value="delete" />
      <button class="btn btn-danger">
        <i class="fa fa-trash-o m-r-sm"> </i>
        #{gettext("Delete")}
      </button>
    </form>
    """
    Phoenix.HTML.raw(html)
  end

  @doc """
  Renders a dropzone form.
  Pass in a `helper` and the `id` we are uploading to.

  ## Example

      dropzone_form(:admin_image_series_path, @series.id)

  """
  def dropzone_form(helper, id) do
    path = Brando.Form.apply_action(helper, :upload_post, id)
    html =
    """
    <form action="#{path}" class="dropzone" id="brando-dropzone"></form>
    <script type="text/javascript">
      Dropzone = require('dropzone');
      Dropzone.options.brandoDropzone = {
        paramName: "image",
        maxFilesize: 10,
        thumbnailHeight: 150,
        thumbnailWidth: 150,
        dictDefaultMessage: '<i class="fa fa-upload fa-4x"></i><br>' +
                            'Trykk eller slipp bilder her for å laste opp'
      };
    </script>
    """
    Phoenix.HTML.raw(html)
  end

  @doc """
  Returns a red X if value is nil
  """
  def check_or_x(nil) do
    ~s(<i class="fa fa-times text-danger"></i>)
  end
  @doc """
  Returns a red X if value is false
  """
  def check_or_x(false) do
    ~s(<i class="fa fa-times text-danger"></i>)
  end
  @doc """
  Returns a green check if value is anything but nil/false
  """
  def check_or_x(_) do
    ~s(<i class="fa fa-check text-success"></i>)
  end

  @doc """
  Displays a banner informing about cookie laws
  """
  def cookie_law(conn, text, button_text \\ "OK") do
    if Map.get(conn.cookies, "cookielaw_accepted") != "1" do
      html =
      """
      <section class="container cookie-container">
        <section class="cookie-container-inner">
          <div class="cookie-law">
            <p>#{text}</p>
            <a href="javascript:Cookielaw.createCookielawCookie();"
               class="dismiss-cookielaw">
              #{button_text}
            </a>
          </div>
        </section>
      </section>
      """
      Phoenix.HTML.raw(html)
    end
  end

  @doc """
  Output Google Analytics code for `code`

  ## Example

      google_analytics("UA-XXXXX-X")

  """
  def google_analytics(code) do
    html =
    """
    <script>
    (function(b,o,i,l,e,r){b.GoogleAnalyticsObject=l;b[l]||(b[l]=
    function(){(b[l].q=b[l].q||[]).push(arguments)});b[l].l=+new Date;
    e=o.createElement(i);r=o.getElementsByTagName(i)[0];
    e.src='//www.google-analytics.com/analytics.js';
    r.parentNode.insertBefore(e,r)}(window,document,'script','ga'));
    ga('create','#{code}','auto');ga('send','pageview');
    </script>
    """
    Phoenix.HTML.raw(html)
  end

  @doc """
  Output frontend admin menu if user is logged in and admin
  """
  def frontend_admin_menu(conn) do
    if current_user(conn) do
      default_img    = "/images/brando/defaults/avatar_default.jpg"
      dashboard_path = Brando.helpers.admin_dashboard_path(conn, :dashboard)
      logout_path    = Brando.helpers.session_path(conn, :logout)
      avatar         = img_url(current_user(conn).avatar, :micro,
                       [default: Brando.helpers.static_path(conn, default_img),
                        prefix: media_url()])
      html =
      """
      <div class="admin-menu">
        <ul class="nav navbar-nav">
          <li class="dropdown">
            <a href="#" class="dropdown-toggle" data-toggle="dropdown"
               role="button" aria-expanded="false">
              <img class="micro-avatar" src="#{avatar}" />
            </a>
            <ul class="dropdown-menu dropdown-menu-right" role="menu">
              <li><a href="#{dashboard_path}">Admin</a></li>
              <li><a href="#{logout_path}">Logg ut</a></li>
            </ul>
          </li>
        </ul>
      </div>
      """
      html |> Phoenix.HTML.raw
    else
      ""
    end
  end

  @doc """
  Render status indicators
  """
  def status_indicators() do
    html =
    """
    <div class="status-indicators pull-left">
      <span class="m-r-sm">
        <span class="status-published">
          <i class="fa fa-circle m-r-sm"> </i>
        </span>
        #{gettext("Published")}
      </span>
      <span class="m-r-sm">
        <span class="status-pending">
          <i class="fa fa-circle m-r-sm"> </i>
        </span>
        #{gettext("Pending")}
      </span>
      <span class="m-r-sm">
        <span class="status-draft">
          <i class="fa fa-circle m-r-sm"> </i>
        </span>
        #{gettext("Draft")}
      </span>
      <span class="m-r-sm">
        <span class="status-deleted">
          <i class="fa fa-circle m-r-sm"> </i>
        </span>
        #{gettext("Deleted")}
      </span>
    </div>
    """
    Phoenix.HTML.raw(html)
  end

  @doc """
  Truncate `text` to `length`
  """
  def truncate(text, len) do
    String.length(text) <= len && text || String.slice(text, 0..len) <> "..."
  end

  @doc """
  Renders a <meta> tag
  """
  def meta_tag(name, content) do
    Phoenix.HTML.Tag.tag(:meta, content: content, name: name)
  end
  def meta_tag({name, content}) do
    Phoenix.HTML.Tag.tag(:meta, content: content, name: name)
  end
  def meta_tag(attrs) when is_list(attrs) do
    Phoenix.HTML.Tag.tag(:meta, attrs)
  end

  @doc """
  Renders all meta/opengraph
  """
  def render_meta(conn) do
    app_name = Brando.config(:app_name)
    title = Brando.Utils.get_page_title(conn)
    conn =
      conn
      |> put_meta("og:title", "#{app_name} | #{title}")
      |> put_meta("og:site_name", app_name)
      |> put_meta("og:type", "article")
      |> put_meta("og:url", Brando.Utils.current_url(conn))

    html = Enum.map_join(get_meta(conn), "\n    ", &(elem(meta_tag(&1), 1)))
    Phoenix.HTML.raw(html)
  end

  @doc """
  Renders opening body tag.

  Checks conn.private for various settings
  """
  def body_tag(conn) do
    id = conn.private[:brando_section_name]
    data_script = conn.private[:brando_section_name]
    classes = conn.private[:brando_css_classes]

    body = "<body"

    if id, do:
      body = body <> ~s( id="#{id}")

    if data_script, do:
      body = body <> ~s( data-script="#{data_script}")

    if classes, do:
      body = body <> ~s( class="#{classes}")

    Phoenix.HTML.raw(body <> ">")
  end

  @doc """
  Formats and shows roles
  """
  def display_roles(roles) do
    roles
    |> List.first
    |> Atom.to_string
  end
end
