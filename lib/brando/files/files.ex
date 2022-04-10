defmodule Brando.Files do
  @moduledoc """
  Context for Files.
  Handles uploads too.
  Interfaces with database
  """

  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.Files.File
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
    |> Brando.repo().insert
  end

  @doc """
  Get file.
  Raises on failure
  """
  def get_file!(id) do
    query =
      from t in File,
        where: t.id == ^id and is_nil(t.deleted_at)

    Brando.repo().one!(query)
  end

  @doc """
  Delete `ids` from database
  """
  def delete_files(ids) when is_list(ids) do
    q = from m in File, where: m.id in ^ids
    Brando.repo().soft_delete_all(q)
  end

  def get_config_for(%{config_target: nil}) do
    Brando.config(Brando.Files)[:default_config]
  end

  def get_config_for(%{config_target: config_target}) when is_binary(config_target) do
    config =
      case String.split(config_target, ":") do
        [type, schema, field_name] when type in ["file"] ->
          schema_module = Module.concat([schema])

          field_name
          |> String.to_atom()
          |> schema_module.__asset_opts__()
          |> Map.get(:cfg)

        ["default"] ->
          Brando.config(Brando.Files)[:default_config]
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
