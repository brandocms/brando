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

  def fetch(url) do
    case Req.get!(url) do
      %{body: body, status: 200} -> {:ok, body}
      _ -> {:error, "oEmbed url not found"}
    end
  end
end
