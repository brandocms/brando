defmodule Brando.Plug.Navigation do
  @moduledoc """
  Add `navigation` to conn assigns

  Plug this in your controller or pipeline

      plug Brando.Plug.Navigation, key: "main"
      plug Brando.Plug.Navigation, key: "footer", as: :footer_navigation

  """

  alias Brando.Cache

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, opts) when is_list(opts) do
    menu_key = Keyword.fetch!(opts, :key)
    name = Keyword.get(opts, :as, :navigation)
    locale = Gettext.get_locale(Brando.web_module(Gettext))
    menu = Cache.Navigation.get("#{menu_key}.#{locale}")
    Plug.Conn.assign(conn, name, menu)
  end

  def call(_, _) do
    raise """
    Brando.Plug.Navigation must be called with a keyword list as arg:

        plug Brando.Plug.Navigation, key: "main", as: :navigation

    """
  end
end
