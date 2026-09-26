defmodule Brando.Content.Proposals.Looks do
  @moduledoc """
  Small renditions of library media for the assistant to look at, when it
  chooses images by what they show.

  Each is a JPEG at most #{256}px on its long edge — about 90 input tokens
  for a model — made from the smallest size the image keeps uncropped, read from
  disk or fetched from the CDN, and cached for an hour, since a run's context is rebuilt for
  every model call. A video is seen through its thumbnail image.
  """
  alias Brando.Images.Utils

  @edge 256
  @ttl :timer.hours(1)
  # Sizes to try when an image has no config.
  @sizes ~w(small medium)

  @doc "The JPEG bytes of `{kind, id}`, or `nil` when there is nothing to show."
  @spec rendition({:image | :video, integer()}) :: binary() | nil
  def rendition({kind, id} = ref) when kind in [:image, :video] and is_integer(id) do
    key = {:proposal_look, Brando.Tenant.Topic.scoped("look"), ref}

    case Brando.Cache.get(key) do
      nil ->
        bytes = make(ref)
        if bytes, do: Brando.Cache.put(key, bytes, @ttl)
        bytes

      bytes ->
        bytes
    end
  end

  def rendition(_), do: nil

  @doc "The token cost a model charges for one rendition, for budget estimates."
  @spec tokens() :: pos_integer()
  def tokens, do: div(@edge * @edge, 750)

  defp make({:image, id}) do
    case Brando.Repo.get(Brando.Images.Image, id) do
      nil -> nil
      image -> image |> source() |> shrink()
    end
  end

  defp make({:video, id}) do
    case Brando.Repo.get(Brando.Videos.Video, id) |> Brando.Repo.preload(:thumbnail) do
      %{thumbnail: %Brando.Images.Image{} = thumbnail} -> thumbnail |> source() |> shrink()
      _ -> nil
    end
  end

  # The bytes of the smallest stored size that shows the whole picture at
  # full rendition size: from disk, or from the CDN.
  defp source(image) do
    paths = Enum.map(sizes(image), &get_in(image.sizes || %{}, [&1])) ++ [image.path]

    Enum.find_value(paths, fn
      nil ->
        nil

      path ->
        case File.read(Utils.media_path(path)) do
          {:ok, bytes} -> bytes
          _ -> nil
        end
    end) || remote(image)
  end

  # Sizes that are not cropped and not smaller than a rendition, smallest first.
  defp sizes(image) do
    case Brando.Images.get_config_for(image) do
      {:ok, %{sizes: sizes}} when is_map(sizes) ->
        for {name, %{"size" => size} = config} <- sizes,
            config["crop"] != true,
            {edge, _} <- [Integer.parse(size)],
            edge >= @edge do
          {edge, name}
        end
        |> Enum.sort()
        |> Enum.map(&elem(&1, 1))

      _ ->
        @sizes
    end
  rescue
    _ -> @sizes
  end

  defp remote(%{cdn: true} = image) do
    size = List.first(sizes(image)) || "original"
    url = Brando.Utils.img_url(image, size, prefix: Brando.Utils.media_url())

    case Req.get(url, receive_timeout: 5_000, retry: false) do
      {:ok, %{status: 200, body: bytes}} when is_binary(bytes) -> bytes
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp remote(_image), do: nil

  defp shrink(nil), do: nil

  defp shrink(bytes) do
    with {:ok, image} <- Image.from_binary(bytes),
         {:ok, small} <- Image.thumbnail(image, @edge),
         {:ok, jpeg} <- Image.write(small, :memory, suffix: ".jpg", quality: 70) do
      jpeg
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
