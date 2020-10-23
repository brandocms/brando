defmodule Brando.Plug.Navigation do
  @moduledoc """
  Add `navigation` to conn assigns

  Plug this in your controller or pipeline

      plug Brando.Plug.Navigation "main"
      plug Brando.Plug.Navigation "footer", as: :footer_navigation

  """

  alias Brando.Cache

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, menu_key, opts \\ []) do
    name = Keyword.get(opts, :as, :navigation)
    locale = Gettext.get_locale(Brando.web_module(Gettext))
    menu = Cache.Navigation.get("#{menu_key}.#{locale}")
    Plug.Conn.assign(conn, name, menu)
  end
end
