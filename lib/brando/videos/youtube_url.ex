defmodule Brando.Videos.YouTubeURL do
  @moduledoc """
  Reads a YouTube video's id from a stored row or a pasted link, and builds the
  embed URL from it, always on YouTube's host: a stored address never reaches an
  iframe as it is.

  `embed_url/2` uses `remote_id` when it reads as an id, so a preview plays what
  the site does, and otherwise the id in `source_url`.

  Handled shapes, with or without a scheme:

      youtube.com/watch?v=dQw4w9WgXcQ
      youtu.be/dQw4w9WgXcQ
      youtube.com/embed/dQw4w9WgXcQ
      youtube-nocookie.com/embed/dQw4w9WgXcQ
      youtube.com/shorts/dQw4w9WgXcQ
      youtube.com/live/dQw4w9WgXcQ
      youtube.com/v/dQw4w9WgXcQ
  """

  @hosts ~w(youtube.com www.youtube.com m.youtube.com music.youtube.com youtube-nocookie.com www.youtube-nocookie.com)
  @short_hosts ~w(youtu.be www.youtu.be)
  @path_prefixes ~w(embed shorts live v)

  @doc """
  Reads the id from a YouTube link. `:error` for anything that is not a video
  link on YouTube's host.
  """
  @spec parse(String.t() | nil) :: {:ok, String.t()} | :error
  def parse(url) when is_binary(url) do
    with %URI{host: host} = uri when is_binary(host) <- url |> String.trim() |> with_scheme() |> URI.parse(),
         id when is_binary(id) <- id_in(String.downcase(host), uri),
         true <- id?(id) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  def parse(_url), do: :error

  @doc "The id of a stored video: `remote_id` when it reads as one, else the id in `source_url`."
  @spec id(map()) :: String.t() | nil
  def id(%{} = video) do
    remote_id = Map.get(video, :remote_id)

    if id?(remote_id) do
      remote_id
    else
      case parse(Map.get(video, :source_url)) do
        {:ok, id} -> id
        :error -> nil
      end
    end
  end

  @doc """
  The embed URL for a stored video, or `nil` when it has no YouTube id. `params`
  are appended as query parameters.
  """
  @spec embed_url(map(), keyword()) :: String.t() | nil
  def embed_url(%{} = video, params \\ []) do
    case {id(video), URI.encode_query(params)} do
      {nil, _query} -> nil
      {id, ""} -> "https://www.youtube.com/embed/#{id}"
      {id, query} -> "https://www.youtube.com/embed/#{id}?#{query}"
    end
  end

  defp id_in(host, %URI{path: path}) when host in @short_hosts do
    case path_segments(path) do
      [id] -> id
      _ -> nil
    end
  end

  defp id_in(host, %URI{path: path, query: query}) when host in @hosts do
    case path_segments(path) do
      ["watch"] when is_binary(query) -> query |> URI.decode_query() |> Map.get("v")
      [prefix, id] when prefix in @path_prefixes -> id
      _ -> nil
    end
  end

  defp id_in(_host, _uri), do: nil

  defp path_segments(nil), do: []
  defp path_segments(path), do: String.split(path, "/", trim: true)

  # A link without a scheme is read as https; `javascript:…` then has the host
  # `javascript`, which is not YouTube's.
  defp with_scheme("//" <> _ = url), do: "https:" <> url

  defp with_scheme(url) do
    if url =~ ~r/\Ahttps?:/i, do: url, else: "https://" <> url
  end

  # `embed/videoseries` is a playlist: the list is in the query, which the embed
  # URL does not carry.
  defp id?("videoseries"), do: false
  defp id?(id), do: is_binary(id) and id =~ ~r/\A[A-Za-z0-9_-]+\z/
end
