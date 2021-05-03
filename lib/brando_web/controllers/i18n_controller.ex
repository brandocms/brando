defmodule Brando.I18nController do
  @moduledoc """
  Controller for i18n actions.
  """

  use BrandoWeb, :controller
  import Brando.I18n

  @doc false
  def switch_language(conn, %{"language" => language}) do
    Gettext.put_locale(Brando.app_module(Gettext), language)

    conn
    |> put_language(language)
    |> redirect(to: "/")
  end
end
