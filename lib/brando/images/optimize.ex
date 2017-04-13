defmodule Brando.Images.Optimize do
  @moduledoc """
  Optimization helpers for Brando images.

  ## Configuration

  This requires you to have `pngquant`/`jpegtran` installed.

  Usually you would want to add this to your `config/prod.exs`:

      config :brando, Brando.Images,
        optimize: [
          png: [
            bin: "/usr/local/bin/pngquant",
            args: "--speed 1 --force --output %{new_filename} -- %{filename}"
          ],
          jpeg: [
            bin: "/usr/local/bin/jpegtran",
            args: "-copy none -optimize -progressive -outfile %{new_filename} %{filename}"
          ]
        ]

  or

      config :brando, Brando.Images,
        optimize: false

  When uploading images through modules (Image, ImageSeries etc) this gets called automatically.

  If you have a `Brando.ImageField`, you must call `optimize/3` in your changeset function

      import Brando.Images.Optimize, only: [optimize: 2]

      def changeset(schema, :create, params) do
        schema
        |> cast(params, @required_fields ++ @optional_fields)
        |> optimize(:avatar)
      end

  """
  require Logger
  alias Ecto.Changeset
  import Brando.Images.Utils, only: [image_type: 1, media_path: 1, optimized_filename: 1]

  @doc """
  Optimize `img`

  Checks image for `optimized` flag, gets the image type and sends off
  to `do_optimize`.
  """
  @spec optimize(Ecto.Changeset.t, :atom | String.t, Keyword.t) :: Ecto.Changeset.t
  def optimize(%Ecto.Changeset{} = changeset, field_name, opts \\ []) do
    force? = Keyword.get(opts, :force, false)

    field_name_atom = is_binary(field_name) && String.to_atom(field_name) || field_name

    with {:ok, img_field} <- check_field_has_changed(changeset, field_name, force?),
         {:ok, _}         <- check_changeset_has_no_errors(changeset),
         {:ok, type}      <- check_valid_image_type(img_field),
         {:ok, cfg}       <- check_image_type_has_config(type)
    do
      do_optimize({cfg, changeset, field_name_atom, img_field})
    else
      _ ->
        changeset
    end
  end

  defp check_image_type_has_config(type) do
    Brando.Images
    |> Brando.config
    |> Keyword.get(:optimize, [])
    |> Keyword.get(type)
    |> case do
      nil -> {:no_config, type}
      cfg -> {:ok, cfg}
    end
  end

  defp check_valid_image_type(img_field) do
    case image_type(img_field.path) do
      :jpeg -> {:ok, :jpeg}
      :png  -> {:ok, :png}
      type  -> {:not_valid, type}
    end
  end

  defp check_field_has_changed(changeset, field_name, true) do
    {:ok, Changeset.get_field(changeset, field_name)}
  end

  defp check_field_has_changed(changeset, field_name, false) do
    case Changeset.get_change(changeset, field_name, nil) do
      nil       -> {:no_change, changeset}
      img_field -> {:ok, img_field}
    end
  end

  defp check_changeset_has_no_errors(%Ecto.Changeset{errors: []} = changeset) do
    {:ok, changeset}
  end

  defp check_changeset_has_no_errors(%Ecto.Changeset{} = changeset) do
    {:has_errors, changeset}
  end

  defp do_optimize(params) do
    params
    |> run_optimizations()
    |> set_optimized_flag()
  end

  defp run_optimizations({cfg, changeset, field_name, img_field}) do
    Enum.map(img_field.sizes, &(Task.async(fn ->
      args = interpolate_and_split_args(elem(&1, 1), cfg[:args])
      execute_command(cfg[:bin], args)
    end)))
    |> Enum.map(&Task.await/1)
    |> Enum.filter(&(&1 != :ok))
    |> case do
      [] -> {:ok, {cfg, changeset, field_name, img_field}}
      _  -> {:error, {cfg, changeset, field_name, img_field}}
    end
  end

  defp execute_command(bin, args) do
    case System.cmd(bin, args) do
      {_, 0}            ->
        :ok
      {msg, error_code} ->
        Logger.error("""
          ==> optimize failed:
          bin..: #{bin}
          args.: #{inspect args}
          msg..: #{inspect msg}
          code.: #{inspect error_code}
        """)
        :error
    end
  end

  defp interpolate_and_split_args(file, args) do
    filename =
      file
      |> media_path
      |> String.replace(" ", "\\ ")

    new_filename =
      file
      |> optimized_filename
      |> media_path
      |> String.replace(" ", "\\ ")

    args
    |> String.split(" ")
    |> Enum.map(&(String.replace(&1, "%{filename}", filename)))
    |> Enum.map(&(String.replace(&1, "%{new_filename}", new_filename)))
  end

  defp set_optimized_flag({:ok, {_, changeset, field_name, img_field}}) do
    img_field = Map.put(img_field, :optimized, true)
    Changeset.put_change(changeset, field_name, img_field)
  end

  defp set_optimized_flag({:error, {_, changeset, _, _}}) do
    changeset
  end
end
