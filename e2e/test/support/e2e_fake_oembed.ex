defmodule E2EFakeOEmbed do
  @moduledoc false
  # YouTube's and Vimeo's oEmbed endpoints for the E2E tests, so a video added
  # from a URL gets its title without the network. The E2E config hands it to
  # `Brando.OEmbed` (the title asked for when the video is created) and to
  # `Brando.Videos.Metadata` (the lookup queued after it) as
  # `req_options: [plug: E2EFakeOEmbed]`.
  #
  # Every video is "Fake oEmbed title", with no thumbnail, so nothing is
  # downloaded. Anything other than an oEmbed endpoint is not found.
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: path} = conn, _opts) when path in [["oembed"], ["api", "oembed.json"]] do
    conn = fetch_query_params(conn)

    json(conn, 200, %{
      "title" => "Fake oEmbed title",
      "description" => "Answered by the E2E server for #{conn.query_params["url"]}",
      "width" => 1280,
      "height" => 720
    })
  end

  def call(conn, _opts), do: json(conn, 404, %{"error" => "not found"})

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
