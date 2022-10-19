defmodule Brando.ErrorView do
  import Brando.Gettext
  require Logger

  @moduledoc """
  Error views for Brando.

  Diffentiates between admin paths and regular paths.
  """
  use BrandoAdmin, :view

  def render("404.html", assigns) do
    render("not_found.html", assigns)
  end

  def render("400.html", assigns) do
    Logger.error("""
    ==> 400 (400.html)

    #{inspect(assigns, pretty: true)}

    """)

    render("bad_request.html", assigns)
  end

  def render("500.html", %{conn: %Plug.Conn{path_info: ["admin" | _]}} = assigns) do
    render("admin_500.html", assigns)
  end

  def render("500.html", %{conn: %Plug.Conn{path_info: [_]}} = assigns) do
    Logger.error("==> 500 (app_error.html)")
    render("catch_all.html", assigns)
  end

  def render("504.html", assigns) do
    render("db_error.html", assigns)
  end

  def render("top.html", assigns) do
    render("_top.html", assigns)
  end

  def render("bottom.html", assigns) do
    render("_bottom.html", assigns)
  end

  def render("feedback.html", %{conn: conn} = assigns) do
    conn = Plug.Conn.fetch_session(conn)
    current_user = Brando.Utils.current_user(conn)
    event_id = Map.get(conn.private, :hrafn_event_id, nil)
    public_dsn = Map.get(conn.private, :hrafn_public_dsn, nil)

    assigns =
      assigns
      |> Map.put(:event_id, event_id)
      |> Map.put(:public_dsn, public_dsn)
      |> Map.put(:current_user, current_user)

    render("_feedback.html", assigns)
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
