defmodule Brando.Videos do
  @moduledoc """
  Context for Videos.
  Handles uploads too.
  Interfaces with database
  """

  use BrandoAdmin, :context
  use Brando.Query

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
        from q in query, where: ilike(q.path, ^"%#{path}%")

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
  end

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
