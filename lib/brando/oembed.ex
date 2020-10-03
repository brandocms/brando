defmodule Brando.OEmbed do
  @providers %{
    "youtube" => "http://www.youtube.com/oembed?format=json&url=",
    "vimeo" => "https://vimeo.com/api/oembed.json?url="
  }

  @spec get(binary, binary) :: {:error, binary} | {:ok, map}
  def get(source, url) do
    fetch(@providers[source] <> URI.encode(url, &URI.char_unreserved?/1))
  end

  def fetch(url) do
    with {:ok, %HTTPoison.Response{body: body}} <-
           HTTPoison.get(url, [], follow_redirect: true, ssl: [{:versions, [:"tlsv1.2"]}]),
         {:ok, struct} <- Poison.decode(body) do
      {:ok, struct}
    else
      _ -> {:error, "oEmbed url not found"}
    end
  end
end
