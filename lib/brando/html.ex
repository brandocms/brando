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
  Creates an URL from a menu item.

  ## Example

      iex> menu_url(conn, {:admin_user_path, :new})

  """
  def menu_url(conn, {fun, action}) do
    apply(helpers(conn), fun, [conn, action])
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
  Return joined path of `file` and the :static_url config option
  as set in your app's config.exs.
  """
  def static_url(file) do
    Path.join([Brando.config(:static_url), file])
  end

  @doc """
  If any javascripts have been assigned to :js_extra on `conn`,
  render each as a <script> tag. If nil, do nothing.
  To assign to `:js_extra`, use `Brando.Utils.add_js/2`
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
  To assign to `:css_extra`, use `Brando.Utils.add_css/2`
  """
  def css_extra(conn) do
    do_css_extra(conn.assigns[:css_extra])
  end

  defp do_css_extra(nil), do: ""
  defp do_css_extra(css) when is_list(css) do
    for c <- css, do: do_css_extra(c)
  end
  defp do_css_extra(css), do: Phoenix.HTML.safe(~s(<link rel="stylesheet" href="#{static_url(css)}">))

  @doc """
  Renders a delete button wrapped in a POST form.
  Pass `record` instance of model, and `helper` path.
  """
  def delete_form_button(record, helper) do
    action = Brando.Form.get_action(helper, :delete, record)
    Phoenix.HTML.safe("""
    <form method="POST" action="#{action}">
      <input type="hidden" name="_method" value="delete" />
      <button class="btn btn-danger">
        <i class="fa fa-trash-o m-r-sm"> </i>
        Slett
      </button>
    </form>
    """)
    # <input type="hidden" name="id" value="#{record.id}" />
  end

  def dropzone_form(helper, id, cfg) do
    _cfg = cfg || Brando.config(Brando.Images)[:default_config]
    path = Brando.Form.get_action(helper, :upload_post, id)
    Phoenix.HTML.safe("""
    <form action="#{path}"
          class="dropzone"
          id="brando-dropzone"></form>
    <script type="text/javascript">
      Dropzone.options.brandoDropzone = {
        paramName: "image", // The name that will be used to transfer the file
        maxFilesize: 10,
        thumbnailHeight: 150,
        thumbnailWidth: 150,
        dictDefaultMessage: '<i class="fa fa-upload fa-4x"></i><br>Trykk eller slipp bilder her for å laste opp'
      };
    </script>
    """)
  end

  def check_or_x(nil) do
    ~s(<i class="fa fa-times text-danger"></i>)
  end
  def check_or_x(false) do
    ~s(<i class="fa fa-times text-danger"></i>)
  end

  def check_or_x(_) do
    ~s(<i class="fa fa-check text-success"></i>)
  end
end