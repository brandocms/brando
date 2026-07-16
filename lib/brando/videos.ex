defmodule Brando.Videos do
  @moduledoc """
  Context for Videos.
  Handles uploads too.
  Interfaces with database
  """

  use BrandoAdmin, :context
  use Brando.Query.Compiler

  import Ecto.Query

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
    config =
      case String.split(config_target, ":") do
        ["video", schema, "function", fn_string] ->
          Brando.Assets.ConfigTarget.config_function!(schema, fn_string)

        ["gallery", schema, "function", fn_string] ->
          schema
          |> Brando.Assets.ConfigTarget.config_function!(fn_string)
          |> gallery_video_config()

        [type, schema, field_name] when type in ["video", "gallery"] ->
          case Brando.Assets.ConfigTarget.schema_module(schema) do
            {:ok, schema_module} ->
              cfg = video_field_cfg(schema_module, field_name)
              if type == "gallery", do: gallery_video_config(cfg), else: cfg

            :error ->
              default_video_config()
          end

        ["default"] ->
          default_video_config()
      end

    {:ok, config}
  end

  def get_config_for(config_target) when is_binary(config_target) do
    get_config_for(%{config_target: config_target})
  end

  def get_config_for(_) do
    get_config_for(%{config_target: "default"})
  end

  defp gallery_video_config(%{video: video}), do: video
  defp gallery_video_config(_), do: default_video_config()

  @doc """
  Whether direct (in-CMS) video upload is actually usable for the given strategy —
  i.e. the provider's credentials are configured. Used to decide whether to offer
  the "Upload file" button (otherwise it's a dead end).

  Defaults to the configured `default_video_upload_strategy`.
  """
  def upload_available?(strategy \\ Brando.default_video_upload_strategy())

  def upload_available?(:mux) do
    cfg = Application.get_env(:brando, Brando.Videos.Uploaders.Mux, [])
    present?(cfg[:access_token_id]) and present?(cfg[:access_token_secret])
  end

  def upload_available?(:bunny) do
    cfg = Application.get_env(:brando, Brando.Videos.Uploaders.Bunny, [])
    present?(cfg[:api_key]) and present?(cfg[:library_id])
  end

  # :local uses the traditional upload flow (not this direct-upload button);
  # :cloudflare / :s3 are not implemented.
  def upload_available?(_strategy), do: false

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  # Resolve the `:cfg` for a "video:Schema:field" config target, tolerating fields
  # that aren't registered schema assets (e.g. block media refs) — returns nil
  # instead of crashing.
  defp video_field_cfg(schema_module, field_name) do
    with {:ok, field_atom} <- existing_atom(field_name),
         %{} = asset <- Brando.Blueprint.Assets.__asset__(schema_module, field_atom),
         opts when is_map(opts) <- Map.get(asset, :opts),
         %{} = cfg <- Map.get(opts, :cfg) do
      cfg
    else
      # Not a registered schema video asset (e.g. a block media ref) — fall back to
      # the default video config so block videos still upload via the default strategy.
      _ -> default_video_config()
    end
  end

  defp default_video_config do
    Brando.config(Brando.Videos)[:default_config] ||
      %{upload_strategy: Brando.default_video_upload_strategy()}
  end

  defp existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
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
