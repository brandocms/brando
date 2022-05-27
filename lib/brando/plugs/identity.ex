defmodule Brando.Plug.Identity do
  @moduledoc """
  Add `identity` to conn assigns
  """
  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _) do
    locale = Gettext.get_locale(Brando.web_module(Gettext))
    identity = Brando.Cache.Identity.get(locale)
    Plug.Conn.assign(conn, :identity, identity)
  end
end
