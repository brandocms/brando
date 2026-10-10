defmodule Brando.OEmbed do
  @moduledoc false
  @providers %{
    "youtube" => "https://www.youtube.com/oembed?format=json&url=",
    "vimeo" => "https://vimeo.com/api/oembed.json?url="
  }

  @spec get(binary, binary) :: {:error, binary} | {:ok, map}
  def get("file", _) do
    {:error, "no oEmbed target"}
  end

  def get(source, url) do
    fetch(@providers[source] <> URI.encode(url, &URI.char_unreserved?/1))
  end

  # An editor is waiting on this, so one attempt with a short timeout, and an
  # error rather than a raise. Req's defaults retry three times over about
  # seven seconds, and `Req.get!/1` raises when the provider can't be reached.
  def fetch(url) do
    [url: url, retry: false, receive_timeout: 5_000, connect_options: [timeout: 5_000]]
    |> Keyword.merge(Keyword.get(Application.get_env(:brando, __MODULE__, []), :req_options, []))
    |> Req.new()
    |> Req.get()
    |> case do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      _ -> {:error, "oEmbed url not found"}
    end
  end
end
