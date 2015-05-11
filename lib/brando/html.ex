defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions.
  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.HTML
      import Brando.HTML.Inspect
      import Brando.HTML.Tablize
      import Brando.Images.Helpers
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
  def render_menu_item(conn, {color, menu}) do
    submenu_items =
      for item <- menu.submenu, do:
        render_submenu_item(conn, item)
    Phoenix.HTML.safe "" <>
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
    "      <span>" <> menu.name <> "</span>" <>
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
      "<li class=\"menuitem " <> active <> "\">" <>
      "  <a href=\"" <> url <> "\" class=\"" <> active <> "\">" <>
      "    <i class=\"fa fa-angle-right\"></i>" <>
      "    <span>" <> item.name <> "</span>" <>
      "  </a>" <>
      "</li>"
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
    |> Phoenix.HTML.safe
  end

  @doc """
  Checks if `conn`'s `full_path` matches `current_path`.
  Returns "active", or "".
  """
  def active_path(conn, url_to_match) do
    if Plug.Conn.full_path(conn) == url_to_match, do: "active", else: ""
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
  def media_url(nil) do
    Brando.config(:media_url)
  end
  def media_url(file) do
    Path.join([Brando.config(:media_url), file])
  end

  @doc """
  Renders a delete button wrapped in a POST form.
  Pass `record` instance of model, and `helper` path.
  """
  def delete_form_button(record, helper) do
    action = Brando.Form.get_action(helper, :delete, record)

    "<form method=\"POST\" action=\"" <> action <> "\">" <>
    "  <input type=\"hidden\" name=\"_method\" value=\"delete\" />" <>
    "  <button class=\"btn btn-danger\">" <>
    "    <i class=\"fa fa-trash-o m-r-sm\"> </i>" <>
    "    Slett" <>
    "  </button>" <>
    "</form>"
    |> Phoenix.HTML.safe
  end

  @doc """
  Renders a dropzone form.
  Pass in a `helper`, the `id` we are uploading to and an optional `cfg`.

  ## Example

      dropzone_form(:admin_image_series_path, @series.id, @series.image_category.cfg)

  """
  def dropzone_form(helper, id, cfg \\ nil) do
    _cfg = cfg || Brando.config(Brando.Images)[:default_config]
    path = Brando.Form.get_action(helper, :upload_post, id)

    "<form action=\"" <> path <> "\"" <>
    "      class=\"dropzone\"" <>
    "      id=\"brando-dropzone\"></form>" <>
    "<script type=\"text/javascript\">" <>
    "  Dropzone.options.brandoDropzone = {" <>
    "    paramName: \"image\", // The name that will be used to transfer the file" <>
    "    maxFilesize: 10," <>
    "    thumbnailHeight: 150," <>
    "    thumbnailWidth: 150," <>
    "    dictDefaultMessage: '<i class=\"fa fa-upload fa-4x\"></i><br>Trykk eller slipp bilder her for å laste opp'" <>
    "  };" <>
    "</script>"
    |> Phoenix.HTML.safe
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
end