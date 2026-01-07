defmodule Brando.Videos do
  @moduledoc """
  Context for Videos.
  Handles uploads too.
  Interfaces with database
  """

  use BrandoAdmin, :context
  use Brando.Query

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

      {:config_target, {type, schema, field}}, query ->
        target_string = "#{type}:#{inspect(schema)}:#{field}"
        from t in query, where: t.config_target == ^target_string

      {:path, path}, query ->
        from q in query, where: ilike(q.path, ^"%#{path}%")
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
    Brando.config(Brando.Videos)[:default_config]
  end

  def get_config_for(%{config_target: config_target}) when is_binary(config_target) do
    config =
      case String.split(config_target, ":") do
        [type, schema, field_name] when type in ["video"] ->
          schema_module = Module.concat([schema])

          field_name_atom = String.to_atom(field_name)

          schema_module
          |> Brando.Blueprint.Assets.__asset_opts__(field_name_atom)
          |> Map.get(:cfg)

        ["default"] ->
          Brando.config(Brando.Videos)[:default_config]
      end

    {:ok, config}
  end

  def get_config_for(config_target) when is_binary(config_target) do
    get_config_for(%{config_target: config_target})
  end

  def get_config_for(_) do
    get_config_for(%{config_target: "default"})
  end
end
