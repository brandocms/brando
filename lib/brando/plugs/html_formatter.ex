defmodule Brando.Plug.HTMLFormatter do
  @moduledoc false
  def init(opts) do
    opts
  end

  def call(conn, _) do
    Plug.Conn.register_before_send(conn, fn conn ->
      formatted_body = Phoenix.LiveView.HTMLFormatter.format(to_string(conn.resp_body), [])
      Plug.Conn.resp(conn, conn.status, formatted_body)
    end)
  end
end
