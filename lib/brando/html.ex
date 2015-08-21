defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  import Brando.Images.Utils, only: [size_dir: 2]
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
  Returns the application name set in config.exs
  """
  def app_name do
    Brando.config(:app_name)
  end

  @doc """
  Returns the Helpers module from the router.
  """
  def helpers(conn) do
    Phoenix.Controller.router_module(conn).__helpers__
  end

  @doc """
  Renders a menu item.
  Also calls to render submenu items, if `current_user` has required role
  """
  def render_menu_item(conn, {color, {name, menu}}) do
    submenu_items =
      for item <- menu.submenu, do:
        render_submenu_item(conn, item)
    Phoenix.HTML.raw "" <>
    "<!-- menu item -->" <>
    "  <li class=\"menuparent\">" <>
    "    <a href=\"#" <> menu.anchor <> "\">" <>
    "      <i class=\"" <> menu.icon <> "\">" <>
    "        <b style=\"background-color: " <> color <> "\"></b>" <>
    "      </i>" <>
    "      <span class=\"pull-right\">" <>
    "        <i class=\"fa fa-angle-down text\"></i>" <>
    "        <i class=\"fa fa-angle-up text-active\"></i>" <>
    "      </span>" <>
    "      <span>" <> name <> "</span>" <>
    "    </a>" <>
    "    <ul class=\"nav lt\">" <>
    "      " <> Enum.join(submenu_items) <>
    "    </ul>" <>
    "  </li>" <>
    "<!-- /menu item -->"
  end

  @doc """
  Creates a menu link from a submenu item.
  Also checks if current_user has required role.
  """
  def render_submenu_item(conn, item) do
    {fun, action} = item.url
    if can_render?(conn, item) do
      url = apply(helpers(conn), fun, [conn, action])
      active = active_path(conn, url)
      li_classes = active && "menuitem active" || "menuitem"
      a_class = active && "active" || ""
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
  Checks if current_user in conn has `role`
  """
  def can_render?(_, %{role: nil}) do
    true
  end
  def can_render?(conn, %{role: role}) do
    if role in current_user(conn).role,
    do: true, else: false
  end
  def can_render?(_, _) do
    true
  end

  @doc """
  Shows link if current_user is authorized for it
  """
  def auth_link(conn, link, role, do: {:safe, block}) do
    do_auth_link("btn-default", conn, link, role, block)
  end
  def auth_link_primary(conn, link, role, do: {:safe, block}) do
    do_auth_link("btn-primary", conn, link, role, block)
  end
  def auth_link_info(conn, link, role, do: {:safe, block}) do
    do_auth_link("btn-info", conn, link, role, block)
  end
  def auth_link_success(conn, link, role, do: {:safe, block}) do
    do_auth_link("btn-success", conn, link, role, block)
  end
  def auth_link_warning(conn, link, role, do: {:safe, block}) do
    do_auth_link("btn-warning", conn, link, role, block)
  end
  def auth_link_danger(conn, link, role, do: {:safe, block}) do
    do_auth_link("btn-danger", conn, link, role, block)
  end
  defp do_auth_link(class, conn, link, role, block) do
    case can_render?(conn, %{role: role}) do
      true ->
        "<a href=\"" <> link <> "\" class=\"btn #{class}\">" <>
        "  " <> to_string(block) <>
        "</a>"
      false ->
        ""
    end
    |> Phoenix.HTML.raw
  end

  @doc """
  Checks if `conn`'s `full_path` matches `current_path`.
  Returns "active", or "".
  """
  def active_path(conn, url_to_match) do
    conn.request_path == url_to_match
  end

  @doc """
  Formats `arg1` (Ecto.DateTime) as a binary.
  """
  def format_date(%Ecto.DateTime{year: year, month: month, day: day}) do
    "#{day}/#{month}/#{year}"
  end

  @doc """
  Return DATE ERROR if `_erroneus_date` is not an Ecto.DateTime
  """
  def format_date(_erroneus_date) do
    ">>DATE ERROR<<"
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
  Return the current user set in session.
  """
  def current_user(conn) do
    Plug.Conn.get_session(conn, :current_user)
  end

  @doc """
  Return joined path of `file` and the :media_url config option
  as set in your app's config.exs.
  """
  def media_url() do
    Brando.config(:media_url)
  end
  def media_url(nil) do
    Brando.config(:media_url)
  end
  def media_url(file) do
    Path.join([Brando.config(:media_url), file])
  end

  @doc """
  Renders a delete button wrapped in a POST form.
  Pass `params` instance of model (if one param), or a list of multiple
  params, and `helper` path.
  """
  @spec delete_form_button(String.t, atom, Keyword.t | %{atom => any}) :: String.t
  def delete_form_button(language, helper, params) do
    action = Brando.Form.apply_action(helper, :delete, params)

    "<form method=\"POST\" action=\"" <> action <> "\">" <>
    "  <input type=\"hidden\" name=\"_method\" value=\"delete\" />" <>
    "  <button class=\"btn btn-danger\">" <>
    "    <i class=\"fa fa-trash-o m-r-sm\"> </i>" <>
    "    #{Brando.Admin.LayoutView.t!(language, "global.delete")}" <>
    "  </button>" <>
    "</form>"
    |> Phoenix.HTML.raw
  end

  @doc """
  Renders a dropzone form.
  Pass in a `helper`, the `id` we are uploading to and an optional `cfg`.

  ## Example

      dropzone_form(:admin_image_series_path, @series.id, @series.image_category.cfg)

  """
  def dropzone_form(helper, id, cfg \\ nil) do
    _cfg = cfg || Brando.config(Brando.Images)[:default_config]
    path = Brando.Form.apply_action(helper, :upload_post, id)

    "<form action=\"" <> path <> "\"" <>
    "      class=\"dropzone\"" <>
    "      id=\"brando-dropzone\"></form>" <>
    "<script type=\"text/javascript\">" <>
    "  Dropzone.options.brandoDropzone = {" <>
    "    paramName: \"image\"," <>
    "    maxFilesize: 10," <>
    "    thumbnailHeight: 150," <>
    "    thumbnailWidth: 150," <>
    "    dictDefaultMessage: '<i class=\"fa fa-upload fa-4x\"></i><br>Trykk eller slipp bilder her for å laste opp'" <>
    "  };" <>
    "</script>"
    |> Phoenix.HTML.raw
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
  Grabs `size` from the `image_field` json struct.
  If default is passed, return size_dir of `default`.
  Returns path to image.
  """
  def img(image_field, size, opts \\ [])
  def img(nil, size, opts) do
    if default = Keyword.get(opts, :default, nil) do
      size_dir(default, size)
    else
      ""
    end
  end

  def img(image_field, size, opts) do
    size = is_atom(size) && Atom.to_string(size) || size
    if prefix = Keyword.get(opts, :prefix, nil) do
      Path.join([prefix, image_field.sizes[size]])
    else
      image_field.sizes[size]
    end
  end

  @doc """
  Displays a banner informing about cookie laws
  """
  def cookie_law(conn, text, button_text \\ "OK") do
    if Map.get(conn.cookies, "cookielaw_accepted") != "1" do
      ~s(<div class="cookie-law"><p>#{text}</p><a href="javascript:Cookielaw.createCookielawCookie\(\);" class="dismiss-cookielaw">#{button_text}</a></div>)
      |> Phoenix.HTML.raw
    end
  end

  @doc """
  Output Google Analytics code for `code`

  ## Example

      analytics("UA-XXXXX-X")

  """
  def analytics(code) do
    "<script>" <>
    "(function(b,o,i,l,e,r){b.GoogleAnalyticsObject=l;b[l]||(b[l]=" <>
    "function(){(b[l].q=b[l].q||[]).push(arguments)});b[l].l=+new Date;" <>
    "e=o.createElement(i);r=o.getElementsByTagName(i)[0];" <>
    "e.src='//www.google-analytics.com/analytics.js';" <>
    "r.parentNode.insertBefore(e,r)}(window,document,'script','ga'));" <>
    "ga('create','#{code}','auto');ga('send','pageview');" <>
    "</script>"
    |> Phoenix.HTML.raw
  end

  @doc """
  Output frontend admin menu if user is logged in and admin
  """
  def frontend_admin_menu(conn) do
    if current_user(conn) do
      """
      <div class="admin-menu">
        <ul class="nav navbar-nav">
          <li class="dropdown">
            <a href="#" class="dropdown-toggle" data-toggle="dropdown" role="button" aria-expanded="false">
              <img class="micro-avatar" src="#{img(current_user(conn).avatar, :micro, [default: Brando.helpers.static_path(conn, "/images/brando/defaults/avatar_default.jpg"), prefix: media_url()])}" />
            </a>
            <ul class="dropdown-menu dropdown-menu-right" role="menu">
              <li><a href="#{Brando.helpers.admin_dashboard_path(conn, :dashboard)}">Admin</a></li>
              <li><a href="#{Brando.helpers.session_path(conn, :logout)}">Logg ut</a></li>
            </ul>
          </li>
        </ul>
      </div>
      """
      |> Phoenix.HTML.raw
    else
      ""
    end
  end

  @doc """
  Render status indicators
  """
  def status_indicators(language) do
    """
    <div class="status-indicators pull-left">
      <span class="m-r-sm"><span class="status-published"><i class="fa fa-circle m-r-sm"> </i> </span> #{Brando.Admin.LayoutView.t!(language, "status.published")}</span>
      <span class="m-r-sm"><span class="status-pending"><i class="fa fa-circle m-r-sm"> </i> </span> #{Brando.Admin.LayoutView.t!(language, "status.pending")}</span>
      <span class="m-r-sm"><span class="status-draft"><i class="fa fa-circle m-r-sm"> </i> </span> #{Brando.Admin.LayoutView.t!(language, "status.draft")}</span>
      <span class="m-r-sm"><span class="status-deleted"><i class="fa fa-circle m-r-sm"> </i> </span> #{Brando.Admin.LayoutView.t!(language, "status.deleted")}</span>
    </div>
    """
    |> Phoenix.HTML.raw
  end
  @doc """
  Truncate `text` to `length`
  """
  def truncate(text, length) do
    String.length(text) <= length && text || String.slice(text, 0..length) <> "..."
  end
end