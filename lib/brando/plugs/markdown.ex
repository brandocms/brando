defmodule Brando.Plug.Markdown do
  @moduledoc """
  Serves an entry's page as Markdown (`Brando.SEO.Markdown`).

  Add it to the endpoint, before the router:

      plug Brando.Plug.Markdown
      plug MyAppWeb.Router

  Two requests get Markdown:

    * the page's URL with `.md` appended, `/projects/sommerro.md`;
    * the page's URL with `text/markdown` preferred in `Accept`.

  The request goes through the router and the page's controller as usual,
  with `.md` taken off the path, so the controller's own rules decide what
  can be seen: drafts, scheduled entries, other sites and pages behind a
  login are not found. When the controller has loaded an entry with a
  Markdown version (passed to `put_meta/3`, `put_hreflang/2` or
  `put_json_ld/3`), its HTML is replaced with the Markdown, with
  `Content-Type: text/markdown`, an `ETag`, `Vary: Accept` and a `Link`
  header naming the HTML page as canonical. Without one, a `.md` request is
  not found, and an `Accept` request gets the HTML.

  HTML responses for an entry with a Markdown version get `Vary: Accept`, so
  caches keep the two apart.

  `.md` never shadows a route of its own: a path that matches a route whose
  last segment is literally `….md` is left alone, as are static files served
  before this plug. Paths under `:except` are left alone too (default
  `["/admin", "/api"]`), for routes that take a `.md` file name as a
  parameter:

      plug Brando.Plug.Markdown, except: ["/admin", "/api", "/docs"]
  """
  @behaviour Plug

  import Plug.Conn

  alias Brando.SEO.Markdown

  @default_except ["/admin", "/api"]

  @impl true
  def init(opts), do: %{except: Keyword.get(opts, :except, @default_except)}

  @impl true
  def call(%Plug.Conn{method: "GET"} = conn, %{except: except}) do
    cond do
      excluded?(conn.request_path, except) -> conn
      md_path?(conn) -> conn |> strip_extension() |> serve(:extension)
      wants_markdown?(conn) -> conn |> put_req_header("accept", "text/html") |> serve(:accept)
      true -> register_before_send(conn, &vary/1)
    end
  end

  def call(conn, _opts), do: conn

  defp serve(conn, mode) do
    conn
    |> put_private(:brando_markdown, mode)
    |> register_before_send(&respond(&1, mode))
  end

  # -- Request -----------------------------------------------------------------

  defp excluded?(path, except), do: Enum.any?(except, &(path == &1 or String.starts_with?(path, &1 <> "/")))

  defp md_path?(%{path_info: path_info} = conn) when path_info != [] do
    last = List.last(path_info)
    String.ends_with?(last, ".md") and last != ".md" and not literal_route?(conn)
  end

  defp md_path?(_conn), do: false

  # A route whose last segment is the literal `….md` is the site's own.
  defp literal_route?(conn) do
    case Phoenix.Router.route_info(Brando.router(), "GET", conn.request_path, conn.host) do
      %{route: route} -> route |> String.split("/") |> List.last() |> String.ends_with?(".md")
      _ -> false
    end
  rescue
    _ -> false
  end

  defp strip_extension(%{path_info: path_info} = conn) do
    last = path_info |> List.last() |> String.replace_suffix(".md", "")
    path_info = List.replace_at(path_info, -1, last)

    # `/index.md` is the site's root.
    path_info = if path_info == ["index"], do: [], else: path_info
    %{conn | path_info: path_info, request_path: "/" <> Enum.join(path_info, "/")}
  end

  @doc """
  Whether an `Accept` header prefers Markdown over HTML: it names
  `text/markdown` with a quality at least that of `text/html`, which it may
  leave out. `*/*` alone is not a preference.

      iex> Brando.Plug.Markdown.prefers_markdown?("text/markdown, text/html;q=0.9")
      true

      iex> Brando.Plug.Markdown.prefers_markdown?("text/html,application/xhtml+xml,*/*;q=0.8")
      false
  """
  @spec prefers_markdown?(String.t()) :: boolean()
  def prefers_markdown?(accept) when is_binary(accept) do
    qualities =
      accept
      |> String.split(",")
      |> Map.new(fn part ->
        [type | params] = part |> String.split(";") |> Enum.map(&String.trim/1)
        {String.downcase(type), quality(params)}
      end)

    markdown = max(Map.get(qualities, "text/markdown", 0.0), Map.get(qualities, "text/x-markdown", 0.0))
    markdown > 0 and markdown >= Map.get(qualities, "text/html", 0.0)
  end

  defp quality(params) do
    Enum.find_value(params, 1.0, fn param ->
      with "q=" <> value <- String.downcase(param),
           {q, _} <- Float.parse(value) do
        q
      else
        _ -> nil
      end
    end)
  end

  defp wants_markdown?(conn) do
    case get_req_header(conn, "accept") do
      [accept | _] -> prefers_markdown?(accept)
      [] -> false
    end
  end

  # -- Response ----------------------------------------------------------------

  defp respond(%{state: :set, status: 200} = conn, mode) do
    entry = conn.private[:brando_page_entry]

    if Markdown.available?(entry) do
      markdown(conn, entry)
    else
      not_markdown(conn, mode)
    end
  end

  defp respond(conn, mode) when mode == :accept, do: vary(conn)
  defp respond(conn, _mode), do: conn

  defp not_markdown(conn, :accept), do: conn

  defp not_markdown(conn, :extension) do
    %{conn | status: 404, resp_body: "Not found\n"}
    |> put_resp_content_type("text/plain")
    |> delete_resp_header("etag")
  end

  defp markdown(conn, entry) do
    body = Markdown.render(entry)
    etag = ~s(W/"md-#{:crypto.hash(:sha256, body) |> Base.url_encode64(padding: false) |> binary_part(0, 22)}")

    conn =
      conn
      |> put_resp_content_type("text/markdown")
      |> put_resp_header("etag", etag)
      |> put_resp_header("vary", "Accept")
      |> put_canonical_link(entry)

    if etag in if_none_match(conn) do
      %{conn | status: 304, resp_body: ""}
    else
      %{conn | resp_body: body}
    end
  end

  defp put_canonical_link(conn, entry) do
    case Brando.Blueprint.URL.resolve(entry, :with_host) do
      url when is_binary(url) and url != "" -> put_resp_header(conn, "link", ~s(<#{url}>; rel="canonical"))
      _ -> conn
    end
  end

  defp if_none_match(conn) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
  end

  # The HTML of a page that also has a Markdown version differs by `Accept`.
  defp vary(%{state: :set} = conn) do
    if Markdown.available?(conn.private[:brando_page_entry]), do: add_vary(conn), else: conn
  end

  defp vary(conn), do: conn

  defp add_vary(conn) do
    case get_resp_header(conn, "vary") do
      [] -> put_resp_header(conn, "vary", "Accept")
      [value | _] -> if value =~ ~r/\baccept\b/i, do: conn, else: put_resp_header(conn, "vary", value <> ", Accept")
    end
  end
end
