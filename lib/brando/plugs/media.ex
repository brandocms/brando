defmodule Brando.Plug.Media do
  @moduledoc """
  Serves uploaded media, from the host's isolated site directory in
  multi-site mode.

  Uploads are editors' files on the site's origin, so every response says
  what it is and that it may run nothing:

    * `X-Content-Type-Options: nosniff`: the type is the one its extension
      gives, never one a browser guesses from the content;
    * `Content-Security-Policy: sandbox`: an SVG or HTML file opened on its
      own is a document with an opaque origin and without scripts, which
      cannot read the site's cookies or the admin. A PDF is left out of it:
      browsers do not show a PDF in a sandboxed document, and their PDF
      viewers keep a PDF's scripts from the page.

  An `<img>`, `<video>` or download is not affected. A web server that serves
  `/media` itself, rather than through this plug, should send the same
  headers (`media_headers/1`).
  """
  import Plug.Conn

  alias Brando.Tenant.Frontend
  alias Brando.Tenant.Storage

  @nosniff {"x-content-type-options", "nosniff"}
  @sandbox {"content-security-policy", "sandbox"}

  @doc """
  The headers a media response for `path` carries: `nosniff`, and the
  `sandbox` policy unless it is a PDF.
  """
  @spec media_headers(String.t()) :: [{String.t(), String.t()}]
  def media_headers(path) do
    if MIME.from_path(path) == "application/pdf", do: [@nosniff], else: [@nosniff, @sandbox]
  end

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

      path ->
        conn =
          conn
          |> put_media_headers(path)
          |> Plug.Static.call(media_opts(conn, opts))

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

  # Set before `Plug.Static` sends the file, and kept on its 304 and 404
  defp put_media_headers(conn, path),
    do: Enum.reduce(media_headers(List.last(path)), conn, fn {k, v}, conn -> put_resp_header(conn, k, v) end)

  defp subset([h | expected], [h | actual]), do: subset(expected, actual)
  defp subset([], actual), do: actual
  defp subset(_, _), do: []
end
