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

  def validate_upload(changeset, {:file, field_name}, user, cfg) do
    do_validate_upload(changeset, {:file, field_name}, user, cfg)
  end

  # TODO: Clean this up -- check focal if image, maybe upload to CDN etc
  defp do_validate_upload(changeset, {_, field_name}, _user, _cfg) do
    with {:ok, field_changes} <- Utils.field_has_changed(changeset, field_name),
         {:ok, _} <- Utils.changeset_has_no_errors(changeset),
         {:ok, :focal_changed} <- check_focal(field_changes) do
      require Logger
      Logger.error("==> FOCAL CHANGED.")
      # Images.Processing.recreate_sizes_for_image_field_record(changeset, field_name, user)
      changeset
    else
      _ -> changeset
    end
  end

  defp check_focal(%{changes: %{path: _}} = changeset) do
    require Logger
    Logger.error(inspect(changeset, pretty: true))
    {:ok, :new_upload}
  end

  defp check_focal(%{changes: %{focal: _}}), do: {:ok, :focal_changed}
  defp check_focal(_), do: {:ok, :focal_unchanged}

  # {:ok, {:upload, upload_params}} ->
  #   with {:ok, _} <- Utils.changeset_has_no_errors(changeset),
  #        {:ok, cfg} <- get_image_cfg(cfg, field_name, changeset),
  #        {:ok, {:handled, name, field}} <-
  #          Images.Upload.Field.handle_upload(field_name, upload_params, cfg, user) do
  #     if CDN.enabled?(), do: CDN.upload_file(changeset, name, field)
  #     put_change(changeset, name, field)
  #   else
  #     :has_errors ->
  #       changeset

  #     {:ok, {:unhandled, _name, _field}} ->
  #       changeset

  #     {:error, {:image_series, :not_found}} ->
  #       add_error(changeset, :image_series, "Image series not found!")

  #     {:error, {name, {:error, error_msg}}} ->
  #       add_error(changeset, name, error_msg)
  #   end

  # defp get_image_cfg(%Type.ImageConfig{} = cfg, _, _) do
  #   {:ok, cfg}
  # end

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
