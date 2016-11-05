defmodule Brando.AuthHandler do
  @moduledoc """
  """
  use Brando.Web, :controller
  import Brando.Gettext

  def unauthenticated(conn, _params) do
    conn
    |> put_flash(:error, gettext("Access denied."))
    |> redirect(to: Brando.helpers.session_path(conn, :login))
  end
end
