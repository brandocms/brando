defmodule Brando.Images.AltText do
  @moduledoc """
  Writes alt text for images in the library by showing them to an AI model.

  The text is written for the image asset's own `alt`, in the site's default
  language: it is what every placement shows unless a picture block or
  gallery overrides it. Asset alt text has one language; placements on
  translated pages override it per entry.

  Each image is sent at a mid-sized rendition rather than the original, which
  is enough to describe it and keeps the cost down. Bulk runs go through
  `Brando.SEO.Suggestions`, so nothing is saved before an editor accepts it.

  Configure a different model or prompt for this through the `:alt` field:

      config :brando, Brando.AI,
        fields: [alt: [model: "anthropic:claude-haiku-4-5", prompt: "…"]]
  """
  import Ecto.Query, only: [from: 2]

  alias Brando.AI
  alias Brando.Images.Image

  @alt_length 125
  # The rendition sent: the smallest configured size at least this wide.
  @target_width 512
  @fallback_sizes ~w(medium small large xlarge)
  @media_types %{
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".png" => "image/png",
    ".webp" => "image/webp",
    ".gif" => "image/gif"
  }

  @doc "The AI options for alt text: the `:alt` field's, or the defaults."
  @spec ai_opts() :: keyword()
  def ai_opts, do: AI.field_ai_opts(Image, :alt)

  @doc """
  Images without alt text that can be described: processed, not deleted,
  and in a format the models read (not SVG). `folder_id` narrows it to one
  folder.
  """
  @spec missing(integer() | nil) :: [Image.t()]
  def missing(folder_id \\ nil) do
    query =
      from i in missing_query(),
        order_by: [desc: i.id],
        select: struct(i, [:id, :path, :title, :width, :height, :sizes, :config_target, :folder_id, :cdn])

    query = if folder_id, do: from(i in query, where: i.folder_id == ^folder_id), else: query
    Brando.Repo.all(query)
  end

  @doc "How many images `missing/1` would list, without loading them."
  @spec missing_count() :: non_neg_integer()
  def missing_count, do: Brando.Repo.aggregate(missing_query(), :count)

  defp missing_query do
    from i in Image,
      where: (is_nil(i.alt) or fragment("trim(?) = ''", i.alt)) and is_nil(i.deleted_at),
      where: i.status == :processed and not ilike(i.path, "%.svg")
  end

  @doc "What describing `images` would cost, per `Brando.AI.Cost.images/2`."
  @spec estimate([Image.t()]) :: {:ok, map()} | {:error, term()}
  def estimate(images), do: Brando.AI.Cost.images(Enum.map(images, &sent_dimensions/1), ai_opts())

  @doc """
  Describes image `id` and returns the text, without saving it.
  """
  @spec describe(integer() | String.t()) :: {:ok, %{text: String.t(), model: String.t()}} | {:error, term()}
  def describe(id) do
    ai_opts = ai_opts()

    with {:ok, image} <- fetch(id),
         {:ok, binary, media_type} <- read(image),
         {:ok, %{text: text, model: model}} <- AI.generate_text(messages(image, binary, media_type, ai_opts), ai_opts) do
      {:ok, %{text: trim(text), model: model}}
    end
  end

  @doc "The prompt an image is described with."
  @spec prompt(map(), keyword()) :: String.t()
  def prompt(image, ai_opts \\ []) do
    base =
      case ai_opts |> Keyword.get(:prompt) |> to_string() |> String.trim() do
        "" ->
          """
          Write the alt text for this image, in #{AI.language_name(Brando.config(:default_language))}. \
          Describe what it shows that matters to someone who cannot see it, in one sentence \
          of at most #{@alt_length} characters. Do not begin with "Image of" or "Picture of". \
          If the image is mostly text, give the text. Plain text, no quotes. \
          Reply with the alt text only.\
          """

        prompt ->
          prompt
      end

    case Map.get(image, :title) do
      title when is_binary(title) and title != "" -> base <> "\n\nThe image's title: " <> title
      _ -> base
    end
  end

  @doc """
  The rendition an image is sent at: the path of the smallest configured size
  at least #{@target_width}px wide, a common size name, or the original.
  """
  @spec rendition(map()) :: String.t()
  def rendition(image) do
    case rendition_key(image) do
      :original -> image.path
      key -> image.sizes[key]
    end
  end

  # The size key sent, or :original when no size will do.
  defp rendition_key(image) do
    sizes = Map.get(image, :sizes) || %{}

    key =
      configured_widths(image)
      |> Enum.filter(fn {key, _width} -> Map.has_key?(sizes, key) end)
      |> Enum.sort_by(&elem(&1, 1))
      |> then(fn widths ->
        Enum.find(widths, fn {_key, width} -> width >= @target_width end) || List.last(widths)
      end)
      |> case do
        {key, _width} -> key
        nil -> Enum.find(@fallback_sizes, &Map.has_key?(sizes, &1))
      end

    path = key && sizes[key]
    if is_binary(path) and Map.has_key?(@media_types, extension(path)), do: key, else: :original
  end

  @doc false
  # The dimensions the rendition has, for the estimate.
  def sent_dimensions(image) do
    width = image.width || 1024
    height = image.height || 768

    target =
      configured_widths(image)
      |> Enum.find_value(fn {key, w} -> sizes_path(image, key) == rendition(image) && w end)

    if target && target < width, do: {target, max(round(height * target / width), 1)}, else: {width, height}
  end

  defp messages(image, binary, media_type, ai_opts) do
    [
      ReqLLM.Context.user([
        ReqLLM.Message.ContentPart.text(prompt(image, ai_opts)),
        ReqLLM.Message.ContentPart.image(binary, media_type)
      ])
    ]
  end

  # Local file first; a CDN-only image is fetched from its public URL.
  defp read(image) do
    path = rendition(image)

    case Map.fetch(@media_types, extension(path)) do
      :error ->
        {:error, :unsupported_format}

      {:ok, media_type} ->
        local = Path.join(Brando.Tenant.Storage.current_media_root(), path)

        cond do
          File.regular?(local) ->
            {:ok, File.read!(local), media_type}

          Map.get(image, :cdn) ->
            image |> Brando.Images.URL.url(rendition_key(image)) |> fetch_remote(media_type)

          true ->
            {:error, :image_file_missing}
        end
    end
  end

  defp fetch_remote("http" <> _ = url, media_type) do
    case Req.get(url, retry: false, receive_timeout: 20_000) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) -> {:ok, body, media_type}
      _ -> {:error, :image_file_missing}
    end
  end

  defp fetch_remote(_url, _media_type), do: {:error, :image_file_missing}

  defp fetch(id) do
    case Brando.Repo.get(Image, id) do
      %Image{} = image -> {:ok, image}
      nil -> {:error, {:image, :not_found}}
    end
  end

  defp configured_widths(image) do
    case Brando.Images.ConfigResolver.get(image) do
      {:ok, %{sizes: sizes}} when is_map(sizes) ->
        for {key, %{"size" => size}} <- sizes,
            key not in ["thumb", "micro"],
            {width, _} <- [Integer.parse(to_string(size))],
            do: {key, width}

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp sizes_path(image, key), do: (Map.get(image, :sizes) || %{})[key]

  defp extension(path), do: path |> Path.extname() |> String.downcase()

  # One sentence, cut back a word at a time if the model ran long.
  defp trim(text) do
    text = text |> String.trim() |> String.trim(~s(")) |> String.trim()

    if String.length(text) <= @alt_length do
      text
    else
      text |> String.slice(0, @alt_length) |> String.replace(~r/\s+\S*$/u, "") |> String.trim_trailing(",")
    end
  end
end
