defmodule Brando.Blueprint.Upload do
  @moduledoc """
  Villain parsing
  """
  alias Brando.Files
  alias Brando.Images
  alias Brando.Utils
  alias Brando.Type
  alias Brando.CDN
  alias Ecto.Changeset
  import Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  def validate_upload(changeset, {:image, field_name}, user, cfg) do
    do_validate_upload(changeset, {:image, field_name}, user, cfg)
  end

  def validate_upload(changeset, {:file, field_name}, _user, cfg) do
    with {:ok, plug} <- Utils.field_has_changed(changeset, field_name),
         {:ok, _} <- Utils.changeset_has_no_errors(changeset),
         {:ok, {:handled, name, field}} <-
           Files.Upload.Field.handle_upload(field_name, plug, cfg) do
      put_change(changeset, name, field)
    else
      :unchanged ->
        changeset

      :has_errors ->
        changeset

      {:error, {name, {:error, error_msg}}} ->
        add_error(changeset, name, error_msg)
    end
  end

  defp do_validate_upload(changeset, {:image, field_name}, user, cfg) do
    case Utils.field_has_changed(changeset, field_name) do
      :unchanged ->
        changeset

      {:ok, _} ->
        changeset

        # {:ok, {:update, update_params}} ->
        #   with {:ok, _} <- Utils.changeset_has_no_errors(changeset),
        #        {:ok, image_data} <- get_image_data(changeset, field_name),
        #        {:ok, changeset} <-
        #          maybe_update_focal(update_params, image_data, changeset, field_name, user) do
        #     changeset
        #   else
        #     :has_errors ->
        #       changeset
        #   end

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
    end
  end

  defp maybe_update_focal(%{focal: _focal} = params, image_data, changeset, field_name, user) do
    changeset = put_change(changeset, field_name, Map.merge(image_data, params))
    Images.Processing.recreate_sizes_for_image_field_record(changeset, field_name, user)
  end

  defp maybe_update_focal(params, image_data, changeset, field_name, _) do
    changeset = put_change(changeset, field_name, Map.merge(image_data, params))
    {:ok, changeset}
  end

  defp get_image_cfg(%{db: true}, _, changeset) do
    image_series_id = get_field(changeset, :image_series_id)
    Images.get_series_config(image_series_id)
  end

  defp get_image_cfg(%Type.ImageConfig{} = cfg, _, _) do
    {:ok, cfg}
  end

  defp get_image_cfg(cfg, _, _) do
    {:ok, Brando.Utils.map_to_struct(cfg, Type.ImageConfig)}
  end

  defp get_image_data(changeset, field_name) do
    case Map.get(changeset.data, field_name, nil) do
      nil ->
        raise "Wanted to update image field, but no data was found!"

      image_data ->
        {:ok, image_data}
    end
  end

  @doc """
  Find image and file attributes and validate upload
  """
  def run_upload_validations(changeset, module, attributes, user, image_db_config) do
    attributes
    |> Enum.filter(&(&1.type in [:image, :file]))
    |> Enum.reduce(changeset, fn %{type: type, name: name}, mutated_changeset ->
      case module.__asset_opts__(name) do
        %{cfg: %{db: true}} ->
          validate_upload(mutated_changeset, {type, name}, user, image_db_config)

        %{cfg: field_cfg} ->
          validate_upload(mutated_changeset, {type, name}, user, field_cfg)
      end
    end)
  end
end
