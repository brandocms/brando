defmodule Brando.Traits.Upload do
  @moduledoc """
  Villain parsing
  """
  use Brando.Trait
  alias Brando.Exception.ConfigError
  alias Brando.Images
  alias Brando.Utils
  alias Brando.Type
  alias Ecto.Changeset
  import Ecto.Changeset

  @type changeset :: Changeset.t()
  @type config :: list()

  def validate(module, _config) do
    if module.__image_fields__ == [] and module.__file_fields__ == [] do
      raise ConfigError,
        message: """
        Resource `#{inspect(module)}` is declaring Brando.Traits.Upload, but there are no attributes of type `:image` or `:file` found.

            attributes do
              attribute :cover, :image
            end
        """
    end

    true
  end

  defp validate_upload(changeset, {:image, field_name}, user, cfg),
    do: do_validate_upload(changeset, {:image, field_name}, user, cfg)

  defp validate_upload(changeset, {:file, field_name}, _user, cfg) do
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

      {:ok, {:update, update_params}} ->
        with {:ok, _} <- Utils.changeset_has_no_errors(changeset),
             {:ok, image_data} <- get_image_data(changeset, field_name),
             {:ok, changeset} <-
               maybe_update_focal(update_params, image_data, changeset, field_name, user) do
          changeset
        else
          :has_errors ->
            changeset
        end

      {:ok, {:upload, upload_params}} ->
        with {:ok, _} <- Utils.changeset_has_no_errors(changeset),
             {:ok, cfg} <- get_image_cfg(cfg, field_name, changeset),
             {:ok, {:handled, name, field}} <-
               Images.Upload.Field.handle_upload(field_name, upload_params, cfg, user) do
          if CDN.enabled?(), do: CDN.upload_file(changeset, name, field)
          put_change(changeset, name, field)
        else
          :has_errors ->
            changeset

          {:ok, {:unhandled, _name, _field}} ->
            changeset

          {:error, {:image_series, :not_found}} ->
            add_error(changeset, :image_series, "Image series not found!")

          {:error, {name, {:error, error_msg}}} ->
            add_error(changeset, name, error_msg)
        end

      {:ok, %Type.Image{}} ->
        # image from API - villain gallery/image
        changeset
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

  defp get_image_cfg(:db, _, changeset) do
    image_series_id = get_field(changeset, :image_series_id)
    Images.get_series_config(image_series_id)
  end

  defp get_image_cfg(cfg, _, _) do
    {:ok, cfg}
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
  Process uploads
  """
  @spec changeset_mutator(module, config, changeset, map | :system) :: changeset
  def changeset_mutator(module, _config, %{valid?: true} = changeset, user) do
    image_changeset =
      Enum.reduce(module.__image_fields__(), changeset, fn f, mutated_changeset ->
        image_cfg =
          f.name
          |> module.__attribute_opts__()
          |> Enum.into(%{})

        validate_upload(mutated_changeset, {:image, f.name}, user, image_cfg)
      end)

    Enum.reduce(module.__file_fields__(), image_changeset, fn f, mutated_changeset ->
      file_cfg =
        f.name
        |> module.__attribute_opts__()
        |> Enum.into(%{})

      validate_upload(mutated_changeset, {:file, f.name}, user, file_cfg)
    end)
  end

  def changeset_mutator(_, _, changeset, _) do
    changeset
  end
end
