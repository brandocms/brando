defmodule Brando.HTML do
  @moduledoc """
  Helper and convenience functions. Imported in Brando.AdminView.
  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.HTML
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
  Creates an URL from a menu item.

  ## Example

      iex> menu_url(conn, {:admin_user_path, :new})

  """
  def menu_url(conn, {fun, action}) do
    apply(helpers(conn), fun, [conn, action])
  end
  @doc """
  Joins the path fragments from `conn`.path_info to a binary.
  """
  def path(conn) do
    Path.join(["/"] ++ conn.path_info)
  end

  @doc """
  Checks if `url_to_match` matches `current_path`.
  Returns "active", or "".
  """
  def is_active?(url_to_match, current_path) when url_to_match == current_path, do: "active"
  def is_active?(_, _), do: ""

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
  def media_url(file) do
    Path.join([Brando.config(:media_url), file])
  end

  @doc """
  Return joined path of `file` and the :static_url config option
  as set in your app's config.exs.
  """
  def static_url(file) do
    Path.join([Brando.config(:static_url), file])
  end

  @doc """
  If any javascripts have been assigned to :js_extra on `conn`,
  render each as a <script> tag. If nil, do nothing.
  To assign to `:js_extra`, use `Brando.Util.add_js/2`
  """
  def js_extra(conn) do
    do_js_extra(conn.assigns[:js_extra])
  end

  defp do_js_extra(nil), do: ""
  defp do_js_extra(js) when is_list(js) do
    for j <- js, do: do_js_extra(j)
  end
  defp do_js_extra(js), do: Phoenix.HTML.safe(~s(<script type="text/javascript" src="#{static_url(js)}" charset="utf-8"></script>))

  @doc """
  If any css files have been assigned to :css_extra on `conn`,
  render each as a <link> tag. If nil, do nothing.
  To assign to `:css_extra`, use `Brando.Util.add_css/2`
  """
  def css_extra(conn) do
    do_css_extra(conn.assigns[:css_extra])
  end

  defp do_css_extra(nil), do: ""
  defp do_css_extra(css) when is_list(css) do
    for c <- css, do: do_css_extra(c)
  end
  defp do_css_extra(css), do: Phoenix.HTML.safe(~s(<link rel="stylesheet" href="#{static_url(css)}">))
end