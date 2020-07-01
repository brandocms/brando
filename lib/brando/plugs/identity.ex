defmodule Brando.Plug.Identity do
  @moduledoc """
  Add `identity` to conn assigns
  """
  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, _) do
    identity = Brando.Cache.get(:identity)
    Plug.Conn.assign(conn, :identity, identity)
  end
end
