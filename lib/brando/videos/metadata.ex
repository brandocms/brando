defmodule Brando.Videos.Metadata do
  @moduledoc """
  Looks up what a video's source knows about it: a poster frame, a title, the
  duration and the size. Videos added by URL arrive with none of this, which
  leaves the library a list of untitled rows without pictures.

    * Vimeo, including Vimeo's progressive file links, and YouTube: oEmbed.
    * Bunny Stream (`…b-cdn.net/{guid}/playlist.m3u8`): the stream's
      `thumbnail.jpg`, and the duration and size from its playlists. Bunny has
      no title without its API.
    * Mux (`stream.mux.com`): the thumbnail.

  Bunny pull zones usually serve only the site's own domain, so every request
  carries the site's URL as its referer.

  Requests use `config :brando, Brando.Videos.Metadata, req_options: [...]`,
  which is how tests stub them.
  """

  alias Brando.Videos.Helpers
  alias Brando.Videos.Video

  @type found :: %{
          optional(:thumbnail_url) => String.t(),
          optional(:title) => String.t(),
          optional(:duration) => number(),
          optional(:width) => pos_integer(),
          optional(:height) => pos_integer()
        }

  @vimeo_oembed "https://vimeo.com/api/oembed.json?url="
  @youtube_oembed "https://www.youtube.com/oembed?format=json&url="
  @vimeo_file ~r{player\.vimeo\.com/(?:progressive_redirect/(?:playback|download)|external)/(\d+)}

  @doc """
  Looks up `video` at its source. Returns only what the source knows, so any
  key may be missing; `{:error, :unsupported}` for sources it cannot read.
  """
  @spec lookup(Video.t()) :: {:ok, found()} | {:error, term()}
  def lookup(%Video{type: :vimeo, remote_id: id}) when is_binary(id) and id != "",
    do: vimeo(id)

  def lookup(%Video{type: :youtube, remote_id: id}) when is_binary(id) and id != "",
    do: oembed(@youtube_oembed <> encode("https://www.youtube.com/watch?v=#{id}"))

  def lookup(%Video{type: :external_file, source_url: url} = video) when is_binary(url) do
    cond do
      match = Regex.run(@vimeo_file, url, capture: :all_but_first) ->
        vimeo(hd(match))

      String.contains?(url, ".b-cdn.net/") and String.ends_with?(url, "/playlist.m3u8") ->
        bunny(url, Helpers.derive_external_thumbnail_url(video))

      thumbnail = Helpers.derive_external_thumbnail_url(video) ->
        {:ok, %{thumbnail_url: thumbnail}}

      true ->
        {:error, :unsupported}
    end
  end

  def lookup(%Video{}), do: {:error, :unsupported}

  @doc """
  Whether the video's source can name it: Vimeo and YouTube can, Bunny and Mux
  streams cannot.
  """
  @spec gives_title?(Video.t()) :: boolean()
  def gives_title?(%Video{type: type}) when type in [:vimeo, :youtube], do: true
  def gives_title?(%Video{type: :external_file, source_url: url}) when is_binary(url), do: Regex.match?(@vimeo_file, url)
  def gives_title?(%Video{}), do: false

  @doc """
  Downloads the image at `url`. Returns its bytes and content type.
  """
  @spec download(String.t()) :: {:ok, binary(), String.t()} | {:error, term()}
  def download(url) do
    case get(url) do
      {:ok, %{status: 200, body: body} = response} when is_binary(body) and body != "" ->
        {:ok, body, content_type(response)}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, _} = error ->
        error
    end
  end

  defp vimeo(id) do
    with {:ok, found} <- oembed(@vimeo_oembed <> encode("https://vimeo.com/#{id}")) do
      # oEmbed answers with a 295×166 thumbnail; the same image is available larger.
      {:ok, Map.update(found, :thumbnail_url, nil, &larger_vimeo_thumbnail/1)}
    end
  end

  defp larger_vimeo_thumbnail(nil), do: nil
  defp larger_vimeo_thumbnail(url), do: String.replace(url, ~r/_\d+x\d+(?=[?\.]|$)/, "_1280")

  defp oembed(url) do
    case get(url) do
      {:ok, %{status: 200, body: %{} = data}} ->
        {:ok,
         compact(%{
           title: blank_to_nil(data["title"]),
           thumbnail_url: data["thumbnail_url"],
           duration: positive(data["duration"])
         })}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, _} = error ->
        error
    end
  end

  # The master playlist names a playlist per rendition; the largest gives the
  # size, and its segments add up to the duration.
  defp bunny(url, thumbnail_url) do
    with {:ok, %{status: 200, body: master}} when is_binary(master) <- get(url),
         {:ok, {width, height, variant}} <- largest_rendition(master) do
      duration =
        case get(URI.merge(url, variant) |> to_string()) do
          {:ok, %{status: 200, body: playlist}} when is_binary(playlist) -> playlist_duration(playlist)
          _ -> nil
        end

      {:ok, compact(%{thumbnail_url: thumbnail_url, width: width, height: height, duration: duration})}
    else
      # The thumbnail alone is still worth having.
      _ -> {:ok, compact(%{thumbnail_url: thumbnail_url})}
    end
  end

  @doc false
  def largest_rendition(master) do
    ~r/#EXT-X-STREAM-INF:[^\n]*RESOLUTION=(\d+)x(\d+)[^\n]*\n([^\n#]+)/
    |> Regex.scan(master, capture: :all_but_first)
    |> Enum.map(fn [w, h, uri] -> {String.to_integer(w), String.to_integer(h), String.trim(uri)} end)
    |> Enum.max_by(fn {w, h, _} -> w * h end, fn -> nil end)
    |> case do
      nil -> {:error, :no_renditions}
      rendition -> {:ok, rendition}
    end
  end

  @doc false
  def playlist_duration(playlist) do
    ~r/#EXTINF:([\d.]+)/
    |> Regex.scan(playlist, capture: :all_but_first)
    |> Enum.map(fn [seconds] -> seconds |> Float.parse() |> elem(0) end)
    |> Enum.sum()
    |> positive()
  end

  defp get(url) do
    [
      url: url,
      retry: false,
      receive_timeout: 15_000,
      headers: [{"referer", Brando.Utils.hostname() <> "/"}]
    ]
    |> Keyword.merge(Keyword.get(Application.get_env(:brando, __MODULE__, []), :req_options, []))
    |> Req.new()
    |> Req.get()
  end

  defp content_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [type | _] -> type |> String.split(";") |> hd() |> String.trim()
      [] -> "image/jpeg"
    end
  end

  defp encode(url), do: URI.encode(url, &URI.char_unreserved?/1)

  defp positive(n) when is_number(n) and n > 0, do: n
  defp positive(_), do: nil

  defp blank_to_nil(text) when is_binary(text), do: if(String.trim(text) == "", do: nil, else: text)
  defp blank_to_nil(_), do: nil

  defp compact(map), do: map |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
end
