defmodule Brando.Plug.Media do
  @moduledoc "Serves media from the host's isolated site directory in multi-site mode."
  import Plug.Conn

  alias Brando.Tenant.Frontend
  alias Brando.Tenant.Storage

  def init(opts) do
    static_opts = [
      at: Keyword.fetch!(opts, :at),
      from: Brando.config(:media_path),
      cache_control_for_etags: (Brando.env() == :prod && "public, max-age=31536000") || false,
      cache_control_for_vsn_requests: (Brando.env() == :prod && "public, max-age=31536000") || false
    ]

    Plug.Static.init(static_opts)
  end

  def call(conn, opts) do
    case subset(opts.at, conn.path_info) do
      [] ->
        conn

      _path_match ->
        conn = Plug.Static.call(conn, media_opts(conn, opts))

        if conn.state in [:sent, :file] do
          conn
        else
          conn
          |> send_resp(404, "not found")
          |> halt()
        end
    end
  end

  defp media_opts(conn, opts) do
    case Brando.Tenant.mode() do
      :multi ->
        case Frontend.resolve(conn.host) do
          {site, _environment} -> Map.put(opts, :from, Storage.media_root(site))
          nil -> Map.put(opts, :from, Path.join(Brando.config(:media_path), "__unresolved_tenant__"))
        end

      _single_or_none ->
        opts
    end
  end

  defp subset([h | expected], [h | actual]), do: subset(expected, actual)
  defp subset([], actual), do: actual
  defp subset(_, _), do: []
end
