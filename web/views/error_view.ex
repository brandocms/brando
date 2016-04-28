defimpl Plug.Exception, for: Postgrex.Error do
  def status(_exception), do: 504
end

defmodule Brando.ErrorView do
  import Brando.Gettext
  @moduledoc """
  Error views for Brando.

  Diffentiates between admin paths and regular paths.
  """
  use Brando.Web, :view

  def render("404.html", assigns) do
    render("not_found.html", assigns)
  end

  def render("500.html", %{conn: %Plug.Conn{path_info: ["admin" | _]}} = assigns) do
    render("admin_500.html", assigns)
  end

  def render("500.html", %{conn: %Plug.Conn{path_info: [_]}} = assigns) do
    render("app_error.html", assigns)
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
    current_user = Brando.Utils.current_user(conn)
    event_id     = Map.get(conn.private, :hrafn_event_id, nil)
    public_dsn   = Map.get(conn.private, :hrafn_public_dsn, nil)

    assigns =
      assigns
      |> Map.put(:event_id, event_id)
      |> Map.put(:public_dsn, public_dsn)
      |> Map.put(:current_user, current_user)

    render("_feedback.html", assigns)
  end

  # In case no render clause matches or no
  # template is found, let's render it as 500
  def template_not_found(_, assigns) do
    render "catch_all.html", assigns
  end
end
