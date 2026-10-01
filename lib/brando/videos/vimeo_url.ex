defmodule Brando.Videos.VimeoURL do
  @moduledoc """
  Reads a Vimeo video's id and privacy hash from the links editors paste.

  An **unlisted** Vimeo video only plays when its embed URL carries the hash
  Vimeo issues with it (`?h=…`). The share link puts that hash in the path —
  `vimeo.com/123456789/abcdef1234` — so taking "everything after `vimeo.com/`"
  as the id, or only the digits, both lose it: the first produces
  `player.vimeo.com/video/123456789/abcdef1234`, the second an embed that Vimeo
  answers with "This video does not exist".

  Nothing is migrated. `id_and_hash/1` reads `source_url` first, which every
  pasted record has kept verbatim, and falls back to `remote_id` — so rows saved
  with the mangled `"123456789/abcdef1234"` id embed correctly as they are.

  Handled shapes:

      vimeo.com/123456789
      vimeo.com/123456789/abcdef1234
      vimeo.com/123456789?share=copy
      vimeo.com/channels/staffpicks/123456789
      vimeo.com/showcase/111/video/123456789
      vimeo.com/manage/videos/123456789/abcdef1234
      player.vimeo.com/video/123456789?h=abcdef1234

  `player.vimeo.com/external/…` and `…/progressive_redirect/…` are file links,
  not embeds, and are left to the `:external_file` path.
  """

  @type parsed :: %{id: String.t(), hash: String.t() | nil}

  @file_link ~r{player\.vimeo\.com/(?:external|progressive_redirect)/}

  @doc """
  Parses a Vimeo URL. Returns `:error` for anything that is not a Vimeo page or
  player link.
  """
  @spec parse(String.t() | nil) :: {:ok, parsed()} | :error
  def parse(url) when is_binary(url) do
    with false <- Regex.match?(@file_link, url),
         %URI{host: host} = uri when is_binary(host) <- URI.parse(with_scheme(url)),
         true <- vimeo_host?(host),
         {:ok, id, rest} <- find_id(path_segments(uri.path)) do
      {:ok, %{id: id, hash: path_hash(rest) || query_hash(uri.query)}}
    else
      _ -> :error
    end
  end

  def parse(_url), do: :error

  @doc """
  The id and hash for a stored video or video-block map: from `source_url` (or a
  block's `url`) when it parses, otherwise from `remote_id`, which older rows
  may hold as `"id/hash"`.
  """
  @spec id_and_hash(map()) :: parsed() | nil
  def id_and_hash(%{} = video) do
    [Map.get(video, :source_url), Map.get(video, :url)]
    |> Enum.find_value(fn url ->
      case parse(url) do
        {:ok, parsed} -> parsed
        :error -> nil
      end
    end)
    |> Kernel.||(from_remote_id(Map.get(video, :remote_id)))
  end

  @doc """
  The player URL for a stored video or block map, with its hash when it has one.
  `params` are appended as query parameters after `h`.
  """
  @spec embed_url(map(), keyword()) :: String.t() | nil
  def embed_url(%{} = video, params \\ []) do
    case id_and_hash(video) do
      %{id: id, hash: hash} -> player_url(id, hash, params)
      nil -> nil
    end
  end

  @doc """
  The canonical page URL, which is what Vimeo's oEmbed endpoint needs to
  resolve an unlisted video.
  """
  @spec page_url(parsed()) :: String.t()
  def page_url(%{id: id, hash: nil}), do: "https://vimeo.com/#{id}"
  def page_url(%{id: id, hash: hash}), do: "https://vimeo.com/#{id}/#{hash}"

  @doc false
  def player_url(id, hash, params \\ []) do
    query =
      [{"h", hash} | Enum.map(params, fn {key, value} -> {to_string(key), value} end)]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> URI.encode_query()

    case query do
      "" -> "https://player.vimeo.com/video/#{id}"
      query -> "https://player.vimeo.com/video/#{id}?#{query}"
    end
  end

  defp from_remote_id(remote_id) when is_binary(remote_id) do
    segments = String.split(remote_id, ~r{[/?]}, trim: true)

    case find_id(segments) do
      {:ok, id, rest} -> %{id: id, hash: path_hash(rest)}
      # Not an id Vimeo issues, but embedded as-is before this module existed;
      # passing it through keeps those embeds exactly as they were.
      :error when segments != [] -> %{id: hd(segments), hash: nil}
      :error -> nil
    end
  end

  defp from_remote_id(_remote_id), do: nil

  # The id is the first all-digit segment. Showcase and album ids come before
  # it in `/showcase/111/video/123`, so in that shape the one after `video`
  # wins.
  defp find_id(segments) do
    segments =
      case Enum.split_while(segments, &(&1 != "video")) do
        {_before, ["video" | after_video]} when after_video != [] -> after_video
        _ -> segments
      end

    case Enum.drop_while(segments, &(not digits?(&1))) do
      [id | rest] -> {:ok, id, rest}
      [] -> :error
    end
  end

  defp path_hash([hash | _rest]), do: if(hash?(hash), do: hash)
  defp path_hash([]), do: nil

  defp query_hash(nil), do: nil

  defp query_hash(query) do
    case URI.decode_query(query) do
      %{"h" => hash} -> if hash?(hash), do: hash
      _ -> nil
    end
  end

  defp path_segments(nil), do: []
  defp path_segments(path), do: String.split(path, "/", trim: true)

  defp vimeo_host?(host), do: host == "vimeo.com" or String.ends_with?(host, ".vimeo.com")

  defp with_scheme("//" <> _ = url), do: "https:" <> url
  defp with_scheme("http" <> _ = url), do: url
  defp with_scheme(url), do: "https://" <> url

  defp digits?(segment), do: segment =~ ~r/\A\d+\z/
  defp hash?(segment), do: segment =~ ~r/\A[0-9a-f]{6,32}\z/i
end
