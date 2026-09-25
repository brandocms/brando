defmodule Brando.Videos do
  @moduledoc """
  Context for Videos.
  Handles uploads too.
  Interfaces with database
  """

  use BrandoAdmin, :context
  use Brando.Query
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias Brando.Assets.{CompletedCallback, ConfigTarget}
  alias Brando.Blueprint.AssetConfigNormalizer
  alias Brando.Type.VideoConfig
  alias Brando.Users.User
  alias Brando.Videos.Video

  @type id :: binary | integer
  @type changeset :: changeset
  @type params :: map
  @type user :: User.t()

  query :single, Video, do: fn query -> from(t in query) end

  matches Video do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
    end
  end

  query :list, Video, do: fn query -> from(t in query) end

  filters Video do
    fn
      {:ids, ids}, query ->
        from t in query, where: t.id in ^ids

      {:config_target, nil}, query ->
        from(t in query)

      {:config_target, "default"}, query ->
        target_string = "default"
        from t in query, where: t.config_target == ^target_string

      {:config_target, target_string}, query when is_binary(target_string) ->
        from t in query, where: t.config_target == ^target_string

      {:config_target, {type, schema, field}}, query ->
        target_string = "#{type}:#{inspect(schema)}:#{field}"
        from t in query, where: t.config_target == ^target_string

      {:path, path}, query ->
        pattern = "%#{path}%"
        encoded_pattern = "%#{URI.encode(path)}%"

        from q in query,
          where:
            ilike(q.title, ^pattern) or ilike(q.source_url, ^pattern) or ilike(q.remote_id, ^pattern) or
              ilike(q.title, ^encoded_pattern) or ilike(q.source_url, ^encoded_pattern) or
              ilike(q.remote_id, ^encoded_pattern)

      # The root: entries without a folder, and those in a folder that is the root itself.
      {:unused, value}, query when value in [true, "true"] ->
        used = from(v in Video, select: v.id) |> Brando.Repo.all() |> list_usage() |> Map.keys()
        from(t in query, where: t.id not in ^used)

      {:unused, _}, query ->
        query

      {:folder_id, {:root, root_folder_ids}}, query ->
        from(t in query, where: is_nil(t.folder_id) or t.folder_id in ^root_folder_ids)

      {:folder_id, folder_id}, query ->
        case normalize_folder_id(folder_id) do
          nil -> from(t in query, where: is_nil(t.folder_id))
          id -> from(t in query, where: t.folder_id == ^id)
        end
    end
  end

  mutation :update, Video

  mutation :delete, Video do
    fn entry ->
      if Brando.Videos.Uploader.get_delete_timing(entry) == :on_delete do
        Brando.Videos.Uploader.delete_remote(entry)
      end

      {:ok, entry}
    end
  end

  @doc """
  Create new video
  """
  @spec create_video(params, user) :: {:ok, Video.t()} | {:error, changeset}
  def create_video(params, user) do
    %Video{}
    |> Video.changeset(params, user)
    |> Brando.Repo.insert()
    |> tap(fn
      {:ok, video} -> maybe_fetch_metadata_on_create(video, user)
      _ -> :ok
    end)
  end

  # Videos added by URL arrive without a thumbnail or a real title; look them up
  # in the background. Off in tests, which stub the lookups where they need them.
  defp maybe_fetch_metadata_on_create(%Video{type: type} = video, user)
       when type in [:external_file, :vimeo, :youtube] do
    if Keyword.get(Application.get_env(:brando, Brando.Videos.Metadata, []), :fetch_on_create, true),
      do: enqueue_metadata([video.id], user)
  end

  defp maybe_fetch_metadata_on_create(_video, _user), do: :ok

  @doc """
  Queues a lookup of each video's thumbnail, title, duration and size at its
  source (see `fetch_metadata/2`). Returns how many were queued.
  """
  @spec enqueue_metadata([integer()], user) :: {:ok, non_neg_integer()}
  def enqueue_metadata(video_ids, %{id: user_id}) do
    jobs =
      Enum.map(video_ids, fn id ->
        %{"video_id" => id, "user_id" => user_id}
        |> Brando.Tenant.Job.attach()
        |> Brando.Worker.VideoMetadata.new()
      end)

    Oban.insert_all(jobs)
    {:ok, length(jobs)}
  end

  @doc """
  Ids of the videos whose source can tell us more than the video knows: no
  thumbnail, or no real title from a source that has one.
  """
  @spec list_video_ids_missing_metadata() :: [integer()]
  def list_video_ids_missing_metadata do
    from(v in Video,
      where: is_nil(v.deleted_at) and v.type in [:external_file, :vimeo, :youtube],
      select: v
    )
    |> Brando.Repo.all()
    |> Enum.filter(&(is_nil(&1.thumbnail_id) or (placeholder_title?(&1) and Brando.Videos.Metadata.gives_title?(&1))))
    |> Enum.map(& &1.id)
  end

  @doc """
  Fills in what the video's source knows and the video lacks: a thumbnail,
  stored as an image, and the title, duration and size. What is already set is
  kept, except a title that is only the file name from the URL.
  """
  @spec fetch_metadata(Video.t(), user) :: {:ok, Video.t()} | {:error, term()}
  def fetch_metadata(%Video{} = video, user) do
    with {:ok, found} <- Brando.Videos.Metadata.lookup(video) do
      params =
        %{
          thumbnail_id: is_nil(video.thumbnail_id) && store_thumbnail(video, found[:thumbnail_url], user),
          title: placeholder_title?(video) && found[:title],
          duration: blank?(video.duration) && found[:duration] && Brando.Videos.Helpers.format_duration(found.duration),
          width: is_nil(video.width) && found[:width],
          height: is_nil(video.height) && found[:height]
        }
        |> Enum.reject(fn {_, value} -> value in [nil, false] end)
        |> Map.new()

      if params == %{}, do: {:ok, video}, else: update_video(video.id, params, user)
    end
  end

  @doc """
  Puts each video's usage (see `list_usage/1`) in its `:usage` field. The
  video listing's `decorate`, so one page costs one lookup.
  """
  @spec put_usage([Video.t()]) :: [Video.t()]
  def put_usage(videos) do
    usage = videos |> Enum.map(& &1.id) |> list_usage()
    Enum.map(videos, &%{&1 | usage: Map.get(usage, &1.id, [])})
  end

  @doc """
  Where each video is used: entries whose blocks place it, galleries holding
  it, and entries holding it in a video field. Returns `%{video_id => usages}`,
  each usage `%{label: String.t(), url: String.t() | nil}`; videos used nowhere
  are left out.
  """
  @spec list_usage([integer()]) :: %{optional(integer()) => [%{label: String.t(), url: String.t() | nil}]}
  def list_usage([]), do: %{}

  def list_usage(video_ids) do
    refs =
      from(r in Brando.Content.Ref,
        where: r.video_id in ^video_ids and not is_nil(r.block_id),
        select: {r.video_id, r.block_id}
      )
      |> Brando.Repo.all()

    entries_by_block =
      refs |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Brando.Content.BlockReferences.list_entries_for_block_ids()

    in_blocks = for {video_id, block_id} <- refs, entry <- Map.get(entries_by_block, block_id, []), do: {video_id, entry}

    in_galleries =
      from(o in Brando.Galleries.GalleryObject,
        where: o.video_id in ^video_ids,
        select: {o.video_id, o.gallery_id},
        distinct: true
      )
      |> Brando.Repo.all()
      |> Enum.map(fn {video_id, gallery_id} -> {video_id, {Brando.Galleries.Gallery, gallery_id}} end)

    usages = Enum.uniq(in_blocks ++ in_galleries ++ list_field_usage(video_ids))
    labels = entry_labels(Enum.map(usages, &elem(&1, 1)))

    usages
    |> Enum.group_by(&elem(&1, 0), fn {_, entry} -> Map.fetch!(labels, entry) end)
    |> Map.new(fn {video_id, entries} -> {video_id, Enum.sort_by(entries, & &1.label)} end)
  end

  # A video picked in a Blueprint's video field carries that field as its
  # config target ("video:MyApp.Case:cover_video"); the entry holds its id.
  defp list_field_usage(video_ids) do
    from(v in Video, where: v.id in ^video_ids and like(v.config_target, "video:%"), select: {v.id, v.config_target})
    |> Brando.Repo.all()
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.flat_map(fn {config_target, ids} ->
      with ["video", schema, field] <- String.split(config_target, ":"),
           {:ok, schema} <- ConfigTarget.schema_module(schema),
           foreign_key = String.to_existing_atom("#{field}_id"),
           true <- foreign_key in schema.__schema__(:fields) do
        from(e in schema, where: field(e, ^foreign_key) in ^ids, select: {field(e, ^foreign_key), e.id})
        |> Brando.Repo.all()
        |> Enum.map(fn {video_id, entry_id} -> {video_id, {schema, entry_id}} end)
      else
        _ -> []
      end
    end)
  rescue
    ArgumentError -> []
  end

  defp entry_labels(entries) do
    titles =
      entries
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {schema, ids} ->
        from(i in Brando.Content.Identifier,
          where: i.schema == ^schema and i.entry_id in ^ids,
          select: {i.entry_id, i.title}
        )
        |> Brando.Repo.all()
        |> Enum.map(fn {id, title} -> {{schema, id}, title} end)
      end)
      |> Map.new()

    Map.new(entries, fn {schema, id} = entry ->
      label =
        case {schema, Map.get(titles, entry)} do
          {Brando.Galleries.Gallery, _} -> gettext("Gallery #%{id}", id: id)
          {_, title} when is_binary(title) and title != "" -> title
          _ -> "##{id}"
        end

      {entry, %{label: label, url: admin_url(schema, id)}}
    end)
  end

  defp admin_url(schema, id) do
    schema.__admin_route__(:update, [id])
  rescue
    _ -> nil
  end

  @doc """
  The video's title as a person would call it: `nil` when it is only the file
  name from its URL (see `placeholder_title?/1`).
  """
  @spec display_title(Video.t()) :: String.t() | nil
  def display_title(%Video{} = video), do: if(placeholder_title?(video), do: nil, else: URI.decode(video.title))

  @doc """
  Whether the video's title says nothing: empty, or just the file name of its
  URL, which is what adding a file by URL puts there.
  """
  @spec placeholder_title?(Video.t()) :: boolean()
  def placeholder_title?(%Video{title: title} = video) do
    blank?(title) or normalize_title(title) == normalize_title(url_file_name(video.source_url))
  end

  defp url_file_name(url) when is_binary(url) do
    case URI.parse(url).path do
      nil -> nil
      path -> path |> Path.basename() |> Path.rootname()
    end
  end

  defp url_file_name(_), do: nil

  defp normalize_title(nil), do: nil

  defp normalize_title(title),
    do: title |> URI.decode() |> String.replace(~r/[_\-\s]+/, " ") |> String.trim() |> String.downcase()

  defp blank?(value), do: value in [nil, ""]

  defp store_thumbnail(_video, nil, _user), do: nil

  defp store_thumbnail(video, url, user) do
    config_target = ConfigTarget.serialize({"image", Video, :thumbnail})

    with {:ok, body, content_type} <- Brando.Videos.Metadata.download(url),
         {:ok, cfg} <- Brando.Images.get_config_for(config_target),
         tmp = Path.join(System.tmp_dir!(), "brando-video-#{video.id}-#{System.unique_integer([:positive])}"),
         :ok <- File.write(tmp, body) do
      try do
        meta = %{path: tmp, config_target: config_target}
        entry = %{client_name: "video-#{video.id}#{extension(content_type)}", client_type: content_type}

        with {:ok, image} <- Brando.Upload.handle_upload(meta, entry, cfg, user),
             {:ok, image} <- Brando.Upload.process_upload(image, cfg, user) do
          image.id
        else
          _ -> nil
        end
      after
        File.rm(tmp)
      end
    else
      _ -> nil
    end
  end

  defp extension("image/png"), do: ".png"
  defp extension("image/webp"), do: ".webp"
  defp extension(_), do: ".jpg"

  @doc """
  Create new video without user (used by uploaders)
  """
  @spec create_video(params) :: {:ok, Video.t()} | {:error, changeset}
  def create_video(params) do
    %Video{}
    |> Video.changeset(params)
    |> Brando.Repo.insert()
  end

  @doc """
  Runs the configured callback when a video first transitions to `:ready`.

  Provider webhooks can repeat ready events. Comparing the persisted state
  before and after the update prevents successful callbacks from running again
  for those duplicate deliveries.
  """
  @spec run_completed_callback_on_ready(struct(), struct(), user()) :: :ok
  def run_completed_callback_on_ready(%Video{status: previous_status}, %Video{status: :ready} = video, user)
      when previous_status != :ready do
    {:ok, config} = get_config_for(video)
    CompletedCallback.run(config, video, user)
  end

  def run_completed_callback_on_ready(%Video{}, %Video{}, _user), do: :ok

  @doc """
  Get video.
  Raises on failure
  """
  def get_video!(id) do
    query =
      from t in Video,
        where: t.id == ^id and is_nil(t.deleted_at)

    Brando.Repo.one!(query)
  end

  @doc """
  Get video by a meta field path and value.

  ## Examples

      iex> get_video_by_meta("mux.upload_id", "upload_123")
      %Video{}

      iex> get_video_by_meta("mux.asset_id", "asset_abc")
      %Video{}
  """
  def get_video_by_meta(field_path, value) do
    # Split the field path to handle nested keys
    keys = String.split(field_path, ".")

    query =
      from v in Video,
        where: fragment("?#>>? = ?", v.meta, ^keys, ^value) and is_nil(v.deleted_at)

    Brando.Repo.one(query)
  end

  def get_config_for(%{config_target: nil}) do
    {:ok, default_video_config()}
  end

  def get_config_for(%{config_target: config_target}) when is_binary(config_target) do
    {:ok, config_target |> String.split(":") |> resolve_config_target()}
  end

  def get_config_for(config_target) when is_binary(config_target) do
    get_config_for(%{config_target: config_target})
  end

  def get_config_for(_) do
    get_config_for(%{config_target: "default"})
  end

  defp resolve_config_target(["video", schema, "function", function]) do
    ConfigTarget.resolved_function_config!(:video, schema, function)
  end

  defp resolve_config_target(["gallery", schema, "function", function]) do
    ConfigTarget.resolved_function_config!(:gallery, schema, function)
    |> gallery_video_config()
  end

  defp resolve_config_target([type, schema, field_name]) when type in ["gallery", "video"] do
    video_field_cfg(type, schema, field_name)
  end

  defp resolve_config_target(["default"]), do: default_video_config()
  defp resolve_config_target(_invalid_target), do: default_video_config()

  defp gallery_video_config(%{video: video}), do: video
  defp gallery_video_config(_), do: default_video_config()

  @doc """
  Whether direct (in-CMS) video upload is actually usable for the given strategy —
  i.e. the provider's credentials are configured. Used to decide whether to offer
  the "Upload file" button (otherwise it's a dead end).

  Defaults to the configured `default_video_upload_strategy`.
  """
  def upload_available?(strategy \\ Brando.default_video_upload_strategy())

  # The credential half is the provider's own `configured?/0`, never re-decided
  # here. The two functions answer different questions — "should the upload
  # control render?" versus "would an API call work?" — but they must not
  # disagree about whether a credential *is* one. They did: `present?/1` below
  # accepts any non-nil non-empty term where the providers require a non-empty
  # binary, so a non-binary credential rendered the button over a provider that
  # would reject the pick during pre-flight validation.
  #
  # What this function legitimately owns is everything `configured?/0`
  # deliberately does not check: the webhook secret, without which an upload
  # starts and never completes, and the routing values. Those keep the looser
  # `present?/1` — `library_id` is an id, not a secret, and an integer is a
  # reasonable way to configure one.
  def upload_available?(:mux) do
    cfg = provider_config(Brando.Videos.Uploaders.Mux)

    Brando.Videos.Uploaders.Mux.configured?() and present?(cfg[:webhook_secret])
  end

  def upload_available?(:bunny) do
    cfg = provider_config(Brando.Videos.Uploaders.Bunny)
    webhook_secret = cfg[:webhook_secret] || cfg[:read_only_api_key]

    Brando.Videos.Uploaders.Bunny.configured?() and present?(cfg[:library_id]) and
      present?(cfg[:cdn_hostname]) and present?(webhook_secret)
  end

  def upload_available?(:cloudflare) do
    cfg = provider_config(Brando.Videos.Uploaders.Cloudflare)

    Brando.Videos.Uploaders.Cloudflare.configured?() and present?(cfg[:webhook_secret])
  end

  # :local uses the traditional upload flow (not this direct-upload button);
  # unsupported strategies are rejected by Blueprint config validation.
  def upload_available?(_strategy), do: false

  @doc false
  def provider_config(provider), do: Application.get_env(:brando, provider, [])

  # Deliberately looser than the providers' own `present?/1`, which requires a
  # non-empty binary. This one guards ids and hostnames, not credentials — see
  # `upload_available?/1`.
  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  # Fields that aren't registered schema assets (for example block media refs)
  # intentionally fall back so block videos keep using the default strategy.
  defp video_field_cfg(type, schema, field_name) do
    expected_type = if type == "gallery", do: :gallery, else: :video

    case ConfigTarget.blueprint_asset(schema, field_name) do
      {:ok, %{type: ^expected_type, opts: opts}} ->
        config = Map.fetch!(opts, :cfg)

        if expected_type == :gallery do
          gallery_video_config(config)
        else
          AssetConfigNormalizer.normalize_resolved_value!(
            :video,
            # `blueprint_asset/2` above already resolved the schema, so
            # serializing here cannot raise — and it canonicalizes the segment
            # ("Elixir.MyApp.Page" -> "MyApp.Page") instead of re-emitting
            # whatever spelling the caller happened to pass.
            ConfigTarget.serialize({"video", schema, field_name}),
            config
          )
        end

      {:ok, %{type: actual_type}} ->
        raise ArgumentError,
              "config_target field #{inspect(schema)}.#{field_name} has type #{inspect(actual_type)}, " <>
                "expected #{inspect(expected_type)}"

      :error ->
        default_video_config()
    end
  end

  defp default_video_config do
    configured =
      Brando.config(Brando.Videos)[:default_config] ||
        %VideoConfig{upload_strategy: Brando.default_video_upload_strategy()}

    AssetConfigNormalizer.normalize_resolved_value!(:video, "default", configured)
  end

  defp normalize_folder_id(nil), do: nil
  defp normalize_folder_id(""), do: nil
  defp normalize_folder_id(folder_id) when is_integer(folder_id), do: folder_id

  defp normalize_folder_id(folder_id) when is_binary(folder_id) do
    case Integer.parse(folder_id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp normalize_folder_id(_), do: nil
end
