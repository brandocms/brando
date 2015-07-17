defmodule Brando.I18nController do
  @moduledoc """
  Controller for i18n actions.
  """
  use Brando.Web, :controller
  import Brando.I18n

  @doc false
  def switch_language(conn, %{"language" => language}) do
    conn
    |> put_language(language)
    |> redirect(to: "/")
  end
end