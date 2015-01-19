defmodule Brando.HTML do

  @doc false
  defmacro __using__(_) do
    quote do
      import Brando.HTML
    end
  end

  def app_name do
    Brando.config(:app_name)
  end

  def path(conn) do
    Path.join(["/"] ++ conn.path_info)
  end

  def is_active?(url_to_match, current_path) when url_to_match == current_path, do: "active"
  def is_active?(_, _), do: ""

  def format_date(%Ecto.DateTime{year: year, month: month, day: day}) do
    "#{day}/#{month}/#{year}"
  end

  def format_date(_erroneus_date) do
    ">>DATE ERROR<<"
  end

  def zero_pad(int) do
    String.rjust(Integer.to_string(int), 3, ?0)
  end

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
  def media_path(file) do
    Path.join([Brando.config(:media_url), file])
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
    for j <- js, do: Phoenix.HTML.safe(~s(<script type="text/javascript" src="#{j}" charset="utf-8"></script>))
  end
  defp do_js_extra(js), do: Phoenix.HTML.safe(~s(<script type="text/javascript" src="#{js}" charset="utf-8"></script>))

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
    for c <- css, do: Phoenix.HTML.safe(~s(<link rel="stylesheet" href="#{c}">))
  end
  defp do_css_extra(css), do: Phoenix.HTML.safe(~s(<link rel="stylesheet" href="#{css}">))
end