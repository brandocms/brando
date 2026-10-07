defmodule Brando.Images.AltText do
  @moduledoc """
  Writes alt text for images in the library by showing them to an AI model.

  The text is written for the image asset's own `alt` — a map of content
  language → text — in every language the image lacks, in one request: the
  image is what costs, so extra languages only add a sentence of output
  each. It is what every placement shows in its entry's language, unless a
  picture block or gallery overrides it.

  Each image is sent at a mid-sized rendition rather than the original, which
  is enough to describe it and keeps the cost down. Bulk runs go through
  `Brando.SEO.Suggestions`, so nothing is saved before an editor accepts it.

  It uses the `:image` model when one is named, else the default:

      config :brando, Brando.AI,
        models: [default: "anthropic:claude-opus-5-5", image: "anthropic:claude-haiku-4-5"]

  The `:alt` field overrides model or prompt for this job alone:

      config :brando, Brando.AI,
        fields: [alt: [model: "anthropic:claude-haiku-4-5", prompt: "…"]]
  """
  import Ecto.Query, only: [from: 2, dynamic: 1, dynamic: 2]

  alias Brando.AI
  alias Brando.Images.Image

  @alt_length 125
  # Per requested language: the reply's sentence, and the prompt's mention.
  @reply_tokens_per_language 60
  @prompt_tokens_per_language 25
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

  @doc "The AI options for alt text: the `:alt` field's, over the `:image` model."
  @spec ai_opts() :: keyword()
  def ai_opts, do: Image |> AI.field_ai_opts(:alt) |> Keyword.put_new(:model, :image)

  @doc "The content languages alt text is written in, the default first."
  @spec languages() :: [String.t()]
  def languages do
    default = to_string(Brando.config(:default_language))
    configured = Enum.map(Brando.config(:languages) || [], &to_string(&1[:value]))
    Enum.uniq([default | configured])
  end

  @doc "The content languages `image` has no alt text in."
  @spec missing_languages(map()) :: [String.t()]
  def missing_languages(image) do
    Enum.filter(languages(), &blank?(lookup(image, &1)))
  end

  defp lookup(image, language) do
    case Map.get(image, :alt) do
      %{} = alt -> Map.get(alt, language)
      _ -> nil
    end
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: true

  @doc """
  Images missing alt text in any content language that can be described:
  processed, not deleted, and in a format the models read (not SVG).
  `folder_id` narrows it to one folder.
  """
  @spec missing(integer() | nil) :: [Image.t()]
  def missing(folder_id \\ nil) do
    query =
      from i in missing_query(),
        order_by: [desc: i.id],
        select: struct(i, [:id, :path, :title, :alt, :width, :height, :sizes, :config_target, :folder_id, :cdn])

    query = if folder_id, do: from(i in query, where: i.folder_id == ^folder_id), else: query
    Brando.Repo.all(query)
  end

  @doc "How many images `missing/1` would list, without loading them."
  @spec missing_count() :: non_neg_integer()
  def missing_count, do: Brando.Repo.aggregate(missing_query(), :count)

  @doc """
  Config targets (`"image:MyApp.Works.Artwork:image"`) of image assets whose
  alt text the site takes from their entry — declared with `alt_from:` on the
  asset, e.g. `asset :image, :image, alt_from: :title, cfg: …`. Their images
  don't need alt text of their own, so they aren't counted as missing it.
  """
  @spec entry_alt_targets() :: [String.t()]
  def entry_alt_targets do
    for blueprint <- Brando.Blueprint.list_blueprints(),
        %{type: :image, name: name, opts: %{alt_from: field}} when not is_nil(field) <-
          Brando.Blueprint.Assets.__assets__(blueprint),
        do: "image:#{inspect(blueprint)}:#{name}"
  end

  @doc "Whether `image`'s alt text comes from its entry (see `entry_alt_targets/0`)."
  @spec alt_from_entry?(map(), [String.t()]) :: boolean()
  def alt_from_entry?(image, targets \\ entry_alt_targets()), do: Map.get(image, :config_target) in targets

  @doc """
  Per content language, how many of the images `missing/1` looks at lack alt
  text in it, and how many there are: `%{"en" => {missing, total}}`.
  """
  @spec missing_count_by_language() :: %{String.t() => {non_neg_integer(), non_neg_integer()}}
  def missing_count_by_language do
    total = Brando.Repo.aggregate(describable_query(), :count)

    Map.new(languages(), fn language ->
      missing =
        from(i in describable_query(), where: fragment("coalesce(btrim(? ->> ?), '') = ''", i.alt, ^language))
        |> Brando.Repo.aggregate(:count)

      {language, {missing, total}}
    end)
  end

  defp missing_query do
    missing_any =
      Enum.reduce(languages(), dynamic(false), fn language, acc ->
        dynamic([i], ^acc or fragment("coalesce(btrim(? ->> ?), '') = ''", i.alt, ^language))
      end)

    from i in describable_query(), where: ^missing_any
  end

  defp describable_query do
    targets = entry_alt_targets()

    # Images in hidden folders (visitors' uploads) are not the site's to describe
    from i in Image,
      left_join: f in Brando.Media.Folder,
      on: f.id == i.folder_id,
      where: is_nil(i.deleted_at) and i.status == :processed and not ilike(i.path, "%.svg"),
      where: is_nil(i.config_target) or i.config_target not in ^targets,
      where: is_nil(f.id) or f.library
  end

  @doc """
  What describing `images` would cost, per `Brando.AI.Cost.images/3`, with
  the output for every language each lacks.
  """
  @spec estimate([Image.t()]) :: {:ok, map()} | {:error, term()}
  def estimate(images) do
    languages = images |> Enum.map(&length(missing_languages(&1))) |> Enum.max(fn -> 1 end) |> max(1)

    Brando.AI.Cost.images(Enum.map(images, &sent_dimensions/1), ai_opts(),
      reply_tokens: @reply_tokens_per_language * languages,
      prompt_tokens: 200 + @prompt_tokens_per_language * languages
    )
  end

  @doc """
  Describes image `id` in every content language it lacks alt text in (all
  of them when it lacks none), or in `languages:`, without saving: `{:ok, %{values: %{language
  => text}, model: model}}`.
  """
  @spec describe(integer() | String.t(), keyword()) :: {:ok, %{values: map(), model: String.t()}} | {:error, term()}
  def describe(id, opts \\ []) do
    ai_opts = ai_opts()

    with {:ok, image} <- fetch(id),
         languages = opts[:languages] || requested_languages(image),
         {:ok, binary, media_type} <- read(image),
         {:ok, %{text: text, model: model}} <-
           AI.generate_text(messages(image, languages, binary, media_type, ai_opts), ai_opts),
         {:ok, values} <- parse(text, languages) do
      {:ok, %{values: fit(values, ai_opts), model: model}}
    end
  end

  # A reply over the limit is sent back once to be shortened, as text only;
  # whatever is still too long after that is cut at a clause (see trim/1).
  defp fit(values, ai_opts) do
    long = for {language, text} <- values, String.length(text) > @alt_length, into: %{}, do: {language, text}

    shortened =
      with true <- long != %{},
           {:ok, %{text: reply}} <- AI.generate_text(shorten_prompt(long), ai_opts),
           {:ok, shorter} <- parse(reply, Map.keys(long)) do
        shorter
      else
        _ -> %{}
      end

    Map.new(values, fn {language, text} -> {language, trim(Map.get(shortened, language, text))} end)
  end

  defp shorten_prompt(long) do
    keys = Enum.map_join(long, ", ", fn {language, _} -> "\"#{language}\": \"…\"" end)
    texts = Enum.map_join(long, "\n", fn {language, text} -> "- #{AI.language_name(language)}: #{text}" end)

    """
    This alt text is longer than #{@alt_length} characters. Rewrite each as one complete sentence of \
    at most #{@alt_length} characters, keeping what matters most. Keep each in its language.

    #{texts}

    Reply with one JSON object and nothing else: {#{keys}}\
    """
  end

  defp requested_languages(image) do
    case missing_languages(image) do
      [] -> languages()
      missing -> missing
    end
  end

  @doc """
  The prompt an image is described with, asking for `languages` as one JSON
  object. Alt text the image already has in other languages is included, so
  the new ones say the same thing.
  """
  @spec prompt(map(), [String.t()], keyword()) :: String.t()
  def prompt(image, languages, ai_opts \\ []) do
    instructions =
      case ai_opts |> Keyword.get(:prompt) |> to_string() |> String.trim() do
        "" ->
          """
          Write alt text for this image. A screen reader reads it aloud in place of the \
          image, as part of the page. Describe what it shows that matters to someone \
          who cannot see it, in one complete sentence of at most #{@alt_length} characters \
          — count them; a short sentence that ends is better than a long one. Leave out \
          photographic style (close-up, black-and-white, shallow focus) unless it is the \
          point of the image, and leave out decorative detail. Name people, places, brands \
          and products only when the image or the details below give them; never guess. \
          Do not begin with "Image of" or "Picture of". If the image is mostly text, give \
          the text. Plain text, no quotes.\
          """

        prompt ->
          prompt
      end

    wanted = Enum.map_join(languages, ", ", fn language -> "\"#{language}\" (#{AI.language_name(language)})" end)
    keys = Enum.map_join(languages, ", ", fn language -> "\"#{language}\": \"…\"" end)

    known =
      for language <- languages() -- languages,
          text = lookup(image, language),
          not blank?(text),
          do: "- #{AI.language_name(language)}: #{text}"

    title =
      case Brando.Images.text(image, :title, nil) do
        nil -> ""
        title -> "\n\nThe image's title: " <> title
      end

    existing = if known == [], do: "", else: "\n\nIts alt text in other languages:\n" <> Enum.join(known, "\n")

    """
    #{instructions}

    Write it in these languages: #{wanted}. Reply with one JSON object and nothing else: {#{keys}}#{title}#{existing}\
    """
  end

  @doc """
  The model's reply as `{:ok, %{language => text}}`, keeping only the languages
  asked for. A reply that is not JSON is taken as the text for a single requested
  language. Returns `{:error, :empty_response}` or `{:error, :invalid_response}`
  when nothing usable remains.
  """
  def parse(text, languages) do
    json = text |> String.trim() |> String.replace(~r/^```(?:json)?\s*|\s*```$/, "")

    case {Jason.decode(json), languages} do
      {{:ok, %{} = map}, _} ->
        values =
          for language <- languages,
              value = Map.get(map, language),
              is_binary(value) and String.trim(value) != "",
              into: %{},
              do: {language, clean(value)}

        if values == %{}, do: {:error, :empty_response}, else: {:ok, values}

      {_, [language]} ->
        case clean(text) do
          "" -> {:error, :empty_response}
          value -> {:ok, %{language => value}}
        end

      _ ->
        {:error, :invalid_response}
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

  # The narrowest size that is wide enough, else the widest there is.
  defp preferred_width(widths) do
    case Enum.split_with(widths, fn {_key, width} -> width >= @target_width end) do
      {[], narrower} -> Enum.max_by(narrower, &elem(&1, 1), fn -> nil end)
      {wide_enough, _narrower} -> Enum.min_by(wide_enough, &elem(&1, 1))
    end
  end

  # The size key sent, or :original when no size will do.
  defp rendition_key(image) do
    sizes = Map.get(image, :sizes) || %{}

    key =
      configured_widths(image)
      |> Enum.filter(fn {key, _width} -> Map.has_key?(sizes, key) end)
      |> preferred_width()
      |> case do
        {key, _width} -> key
        nil -> Enum.find(@fallback_sizes, &Map.has_key?(sizes, &1))
      end

    path = key && sizes[key]
    if is_binary(path) and Map.has_key?(@media_types, extension(path)), do: key, else: :original
  end

  # The dimensions the rendition has, for the estimate.
  defp sent_dimensions(image) do
    width = image.width || 1024
    height = image.height || 768

    target =
      configured_widths(image)
      |> Enum.find_value(fn {key, w} -> sizes_path(image, key) == rendition(image) && w end)

    if target && target < width, do: {target, max(round(height * target / width), 1)}, else: {width, height}
  end

  defp messages(image, languages, binary, media_type, ai_opts) do
    [
      ReqLLM.Context.user([
        ReqLLM.Message.ContentPart.text(prompt(image, languages, ai_opts)),
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

  defp clean(text), do: text |> String.trim() |> String.trim(~s(")) |> String.trim()

  @doc """
  Cleans the text and fits it to the alt text limit, as a last resort for text
  still over it: cut at the last sentence or clause that fits and end it with a
  full stop, so it reads as finished. Only when no clause keeps half the limit
  does it cut at a word, with an ellipsis to show the cut.
  """
  def trim(text) do
    text = clean(text)
    if String.length(text) <= @alt_length, do: text, else: cut(text)
  end

  defp cut(text) do
    head = String.slice(text, 0, @alt_length)

    clause =
      ~r/[.!?;:,\x{2013}\x{2014}](?=\s|$)/u
      |> Regex.scan(head <> " ", return: :index)
      |> List.last()
      |> case do
        [{at, length}] -> head |> binary_part(0, at + length) |> finish()
        nil -> ""
      end

    if String.length(clause) >= div(@alt_length, 2) do
      clause
    else
      String.replace(head, ~r/\s+\S*$/u, "") <> "\u2026"
    end
  end

  defp finish(clause) do
    clause = String.replace(clause, ~r/[\s,;:\x{2013}\x{2014}]+$/u, "")
    if String.ends_with?(clause, [".", "!", "?"]), do: clause, else: clause <> "."
  end
end
