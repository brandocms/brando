defimpl Plug.Exception, for: Postgrex.Error do
  def status(_exception), do: 504
end

defmodule Brando.ErrorView do
  @moduledoc """
  Error views for Brando.

  Diffentiates between admin paths and regular paths.
  """
  use Brando.Web, :view

  def render("404.html", assigns) do
    render("not_found.html", assigns)
  end

  def render("500.html", %{conn: %Plug.Conn{path_info: ["admin" | _rest]}} = assigns) do
    render("admin_500.html", assigns)
  end

  def render("500.html", %{conn: %Plug.Conn{path_info: [_rest]}} = assigns) do
    render("app_error.html", assigns)
  end

  def render("504.html", assigns) do
    render("db_error.html", assigns)
  end

  # In case no render clause matches or no
  # template is found, let's render it as 500
  def template_not_found(_, assigns) do
    render "catch_all.html", assigns
  end
end