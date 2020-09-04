defmodule Brando.Plug.Navigation do
  @moduledoc """
  Add `navigation` to conn assigns
  """
  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, menu_key) do
    locale = Gettext.get_locale(Brando.app_module(Gettext))
    {:ok, navigation} = Brando.Navigation.get_menu(menu_key, locale)
    Plug.Conn.assign(conn, :navigation, navigation)
  end
end
