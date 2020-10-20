defmodule Brando.Plug.Navigation do
  @moduledoc """
  Add `navigation` to conn assigns
  """

  alias Brando.Cache

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, menu_key) do
    locale = Gettext.get_locale(Brando.web_module(Gettext))
    menu = Cache.Navigation.get("#{menu_key}.#{locale}")
    Plug.Conn.assign(conn, :navigation, menu)
  end
end
