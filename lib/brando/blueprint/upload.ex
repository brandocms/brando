defmodule Brando.Blueprint.Upload do
  @moduledoc """
  Villain parsing
  """
  alias Brando.Images
  alias Brando.Utils
  alias Brando.Type
  alias Brando.CDN
  alias Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  def validate_upload(changeset, {:image, field_name}, user, cfg) do
    do_validate_upload(changeset, {:image, field_name}, user, cfg)
  end

  def validate_upload(changeset, {:gallery, field_name}, user, cfg) do
    do_validate_upload(changeset, {:gallery, field_name}, user, cfg)
  end

  def validate_upload(changeset, {:file, field_name}, user, cfg) do
    do_validate_upload(changeset, {:file, field_name}, user, cfg)
  end

  defp do_validate_upload(changeset, {:image, _field_name}, _user, _cfg) do
    changeset
  end

  defp do_validate_upload(changeset, {:file, _field_name}, _user, _cfg) do
    changeset
  end

  defp do_validate_upload(changeset, {:gallery, _field_name}, _user, _cfg) do
    changeset
  end

  defp get_image_cfg(cfg, _, _) do
    {:ok, Brando.Utils.map_to_struct(cfg, Type.ImageConfig)}
  end

  @doc """
  Find assets and validate upload
  """
  def run_upload_validations(changeset, module, assets, user) do
    assets
    |> Enum.filter(&(&1.type in [:image, :file, :gallery]))
    |> Enum.reduce(changeset, fn %{type: type, name: name}, mutated_changeset ->
      %{cfg: field_cfg} = module.__asset_opts__(name)
      validate_upload(mutated_changeset, {type, name}, user, field_cfg)
    end)
  end
end
