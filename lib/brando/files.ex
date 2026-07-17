defmodule Brando.Files do
  @moduledoc """
  Context for Files.
  Handles uploads too.
  Interfaces with database
  """

  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.Assets.ConfigTarget
  alias Brando.Blueprint.AssetConfigNormalizer
  alias Brando.Files.File
  alias Brando.Type.FileConfig
  alias Brando.Users.User

  @type id :: binary | integer
  @type changeset :: changeset
  @type params :: map
  @type user :: User.t()

  query :single, File, do: fn query -> from(t in query) end

  matches File do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id
    end
  end

  query :list, File, do: fn query -> from(t in query) end

  filters File do
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

      {:folder_id, folder_id}, query ->
        case normalize_folder_id(folder_id) do
          nil -> from(t in query, where: is_nil(t.folder_id))
          id -> from(t in query, where: t.folder_id == ^id)
        end
    end
  end

  mutation :update, File
  mutation :delete, File

  @doc """
  Create new file
  """
  @spec create_file(params, user) :: {:ok, File.t()} | {:error, changeset}
  def create_file(params, user) do
    %File{}
    |> File.changeset(params, user)
    |> Brando.Repo.insert()
  end

  @doc """
  Get file.
  Raises on failure
  """
  def get_file!(id) do
    query =
      from t in File,
        where: t.id == ^id and is_nil(t.deleted_at)

    Brando.Repo.one!(query)
  end

  @doc """
  Delete `ids` from database
  """
  def delete_files(ids) when is_list(ids) do
    q = from m in File, where: m.id in ^ids
    Brando.Repo.soft_delete_all(q)
  end

  @doc """
  Get configuration for a file's `config_target`

  Returns its configuration or the default configuration if none is found
  """
  def get_config_for(%{config_target: nil}) do
    {:ok, default_file_config()}
  end

  def get_config_for(%{config_target: config_target}) when is_binary(config_target) do
    config =
      case String.split(config_target, ":") do
        [type, schema, "function", fn_string] when type in ["file", "video"] ->
          ConfigTarget.resolved_function_config!(config_type(type), schema, fn_string)

        # "video:" — files wrapped by :upload videos resolve their path
        # through the owning video asset's cfg (VideoConfig has upload_path)
        [type, schema, field_name] when type in ["file", "video"] ->
          field_config!(config_type(type), schema, field_name)

        ["default"] ->
          default_file_config()
      end

    {:ok, config}
  end

  def get_config_for(config_target) when is_binary(config_target) do
    get_config_for(%{config_target: config_target})
  end

  def get_config_for(_) do
    get_config_for(%{config_target: "default"})
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

  defp config_type("file"), do: :file
  defp config_type("video"), do: :video

  defp field_config!(expected_type, schema, field_name) do
    case ConfigTarget.blueprint_asset(schema, field_name) do
      {:ok, %{type: ^expected_type, opts: opts}} ->
        config = Map.fetch!(opts, :cfg)
        target = "#{expected_type}:#{schema}:#{field_name}"
        AssetConfigNormalizer.normalize_resolved_value!(expected_type, target, config)

      {:ok, %{type: actual_type}} ->
        raise ArgumentError,
              "config_target field #{inspect(schema)}.#{field_name} has type #{inspect(actual_type)}, " <>
                "expected #{inspect(expected_type)}"

      :error ->
        raise ArgumentError,
              "invalid config_target field #{inspect(field_name)} for Blueprint #{inspect(schema)}"
    end
  end

  defp default_file_config do
    configured = Brando.config(Brando.Files)[:default_config] || FileConfig.default_config()
    AssetConfigNormalizer.normalize_resolved_value!(:file, "default", configured)
  end
end
