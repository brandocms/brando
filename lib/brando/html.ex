defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  @type alert_levels :: :default | :primary | :info | :success | :warning | :danger

  import Brando.Gettext
  import Brando.Utils, only: [current_user: 1, active_path?: 2]
  import Brando.Meta.Controller, only: [put_meta: 3, get_meta: 1, get_meta: 2]

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.HTML
      import Brando.HTML.Inspect
      import Brando.HTML.Tablize
    end
  end

  @doc """
  Renders a menu item.
  Also calls to render submenu items, if `current_user` has required role
  """
  def render_menu_item(conn, {color, menu}) do
    submenu_items = Enum.map_join(menu.submenu, "\n", &render_submenu_item(conn, &1))

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
    Phoenix.HTML.raw(html)
  end

  @doc """
  Creates a menu link from a submenu item.
  Also checks if current_user has required role.
  """
  def render_submenu_item(conn, item) do
    {fun, action} = item.url

    if can_render?(conn, item) do
      url        = apply(Brando.Utils.helpers(conn), fun, [conn, action])
      active?    = active_path?(conn, url)
      li_classes = active? && "menuitem active" || "menuitem"
      a_class    = active? && "active" || ""

      """
      <li class="#{li_classes}">
        <a href="#{url}" class="#{a_class}">
          <i class="fa fa-angle-right"></i>
          <span>#{item.name}</span>
        </a>
      </li>
      """
    else
      ""
    end
  end

  @doc """
  Returns `active` if `conn`'s `full_path` matches `current_path`.
  """
  @spec active(Plug.Conn.t, String.t) :: String.t
  def active(conn, url_to_match, add_class? \\ nil) do
    result = add_class? && ~s(class="active") || "active"
    active_path?(conn, url_to_match) && result || ""
  end

  @doc """
  Checks if current_user in conn has `role`
  """
  @spec can_render?(Plug.Conn.t, map) :: boolean
  def can_render?(_, %{role: nil}) do
    true
  end
  def can_render?(conn, %{role: role}) do
    current_user = current_user(conn)

    if current_user do
      role in current_user(conn).role && true || false
    else
      false
    end
  end
  def can_render?(_, _) do
    true
  end

  @doc """
  Shows `content` if `current_user` has `role` that allows it.
  """
  @spec auth_content(Plug.Conn.t, atom, [{:do, term}]) :: {:safe, String.t}
  def auth_content(conn, role, do: {:safe, block}) do
    html = can_render?(conn, %{role: role}) && block || ""
    Phoenix.HTML.raw(html)
  end

  @doc """
  Shows `link` if `current_user` has `role` that allows it.
  """
  @spec auth_link(Plug.Conn.t, String.t, atom, [{:do, term}]) :: {:safe, String.t}
  def auth_link(conn, link, role, do: {:safe, block}) do
    do_auth_link({"btn-default", conn, link, role}, block)
  end
  @doc """
  Shows `link` with `type` if `current_user` has `role` that allows it.
  """
  @spec auth_link(alert_levels, Plug.Conn.t, String.t, atom, [{:do, term}]) :: {:safe, String.t}
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
  Zero pad `val` as a binary.

  ## Example

      iex> zero_pad(5)
      "005"

  """
  def zero_pad(str, count \\ 3)
  def zero_pad(val, count) when is_binary(val) do
    String.rjust(val, count, ?0)
  end
  def zero_pad(val, count) do
    String.rjust(Integer.to_string(val), count, ?0)
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
  Pass `params` instance of schema (if one param), or a list of multiple
  params, and `helper` path.
  """
  @spec delete_form_button(atom, Keyword.t | %{atom => any}) :: {:safe, String.t}
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
  Renders a post button
  """
  def post_form_button(text, helper, controller_action, params \\ nil) do
    action = Brando.Form.apply_action(helper, controller_action, params)
    """
    <form method="POST" action="#{action}">
      <input type="hidden" name="_method" value="post" />
      <button class="btn btn-danger">
        <i class="fa fa-exclamation-circle m-r-sm"> </i>
        #{text}
      </button>
    </form>
    """ |> Phoenix.HTML.raw
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
    <form action="#{path}" class="dzone" id="brando-dropzone"></form>
    """
    Phoenix.HTML.raw(html)
  end

  @doc """
  Returns a red X if value is nil
  """
  def check_or_x(nil) do
    ~s(<i class="icon-centered fa fa-times text-danger"></i>)
  end
  @doc """
  Returns a red X if value is false
  """
  def check_or_x(false) do
    ~s(<i class="icon-centered fa fa-times text-danger"></i>)
  end
  @doc """
  Returns a green check if value is anything but nil/false
  """
  def check_or_x(_) do
    ~s(<i class="icon-centered fa fa-check text-success"></i>)
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
  Render status indicators
  """
  def status_indicators do
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
  def truncate(nil, _) do
    ""
  end

  def truncate(text, len) when is_binary(text) do
    String.length(text) <= len && text || String.slice(text, 0..len) <> "..."
  end

  def truncate(val, _) do
    val
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
      |> put_meta("og:title", "#{title}")
      |> put_meta("og:site_name", app_name)
      |> put_meta("og:type", "article")
      |> put_meta("og:url", Brando.Utils.current_url(conn))

    conn =
      case get_meta(conn, "og:image") do
        nil -> conn
        img ->
          if String.contains?(img, "://") do
            conn
          else
            put_meta(conn, "og:image", Path.join("#{conn.scheme}://#{conn.host}", img))
          end
      end

    html = Enum.map_join(get_meta(conn), "\n    ", &(elem(meta_tag(&1), 1)))
    Phoenix.HTML.raw("    #{html}")
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

    body =
      if id, do:
        body <> ~s( id="#{id}"),
      else:
        body

    body =
      if data_script, do:
        body <> ~s( data-script="#{data_script}"),
      else:
        body

    body =
      if classes, do:
        body <> ~s( class="#{classes}"),
      else:
        body

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

  @doc """
  Checks if conn.scheme is :https. If not, warn and provide link to secure login.
  """
  def insecure_login?(conn) do
    if Brando.config(:warn_on_http_auth) do
      if conn.scheme != :https do
        ~s(<div class="text-center alert alert-block alert-danger">) <>
        gettext("You are trying to authorize from an insecure URL. " <>
                "<a href=\"%{url}\">Please try again from this URL</a> " <>
                "or proceed at your own risk!", url: Brando.Utils.https_url(conn)) <>
        ~s(</div>)
        |> Phoenix.HTML.raw
      end
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
      """ |> Phoenix.HTML.raw
    end
  end

  @doc """
  Outputs an `img` tag marked as safe html

  ## Options:

    * `prefix` - string to prefix to the image's url. I.e. `prefix: media_url()`
    * `default` - default value if `image_field` is nil. Does not respect `prefix`, so use
      full path.
    * `srcset` - if you want to use the srcset attribute. Set in the form of `{module, field}`.
      I.e `srcset: {Brando.User, :avatar}`

  """
  def img_tag(image_field, size, opts \\ []) do
    srcset_attr = get_srcset(image_field, opts[:srcset], opts) || []
    attrs =
      Keyword.new
      |> Keyword.put(:src, Brando.Utils.img_url(image_field, size, opts))
      |> Keyword.merge(Keyword.drop(opts, [:prefix, :srcset, :default]) ++ srcset_attr)

    Phoenix.HTML.Tag.tag(:img, attrs)
  end

  defp get_srcset(_, nil, _) do
    nil
  end

  defp get_srcset(image_field, {mod, field}, opts) do
    {:ok, cfg} = apply(mod, :get_image_cfg, [field])
    if !cfg.srcset do
      raise ArgumentError, message: "no `:srcset` key set in #{inspect mod}'s #{inspect field} image config"
    end

    srcset_values =
      for {k, v} <- cfg.srcset do
        path = Brando.Utils.img_url(image_field, k, opts)
        "#{path} #{v}"
      end

    [srcset: Enum.join(srcset_values, ", ")]
  end
end
