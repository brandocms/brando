defmodule Brando.Plug.Media do
  import Plug.Conn

  def init(opts) do
    static_opts = [
      at: Keyword.fetch!(opts, :at),
      from: Brando.config(:media_path),
      cache_control_for_etags: (Brando.env() == :prod && "public, max-age=31536000") || false,
      cache_control_for_vsn_requests:
        (Brando.env() == :prod && "public, max-age=31536000") || false
    ]

    Plug.Static.init(static_opts)
  end

  def call(conn, opts) do
    case subset(opts.at, conn.path_info) do
      [] ->
        conn

      _path_match ->
        case Plug.Static.call(conn, opts) do
          %Plug.Conn{status: 200} = conn ->
            conn

          %Plug.Conn{} = conn ->
            conn |> send_resp(404, "not found") |> halt()
        end
    end
  end

  defp subset([h | expected], [h | actual]), do: subset(expected, actual)
  defp subset([], actual), do: actual
  defp subset(_, _), do: []
end
