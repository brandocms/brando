defmodule Brando.Plug.NoIndex do
  @moduledoc """
  A plug to prevent robot indexing by adding a `X-Robots-Tag: noindex, nofollow`
  response header
  """

  @behaviour Plug

  def init(_params), do: nil

  def call(conn, _params) do
    Plug.Conn.put_resp_header(conn, "X-Robots-Tag", "noindex, nofollow")
  end
end
