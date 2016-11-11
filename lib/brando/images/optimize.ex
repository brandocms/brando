defmodule Brando.Images.Optimize do
  @moduledoc """
  Optimization helpers for Brando images.

  ## Configuration

  This requires you to have `pngquant`/`cjpeg` installed.

  Usually you would want to add this to your `config/prod.exs`:

      config :brando, Brando.Images,
        optimize: [
          png: [
            bin: "/usr/local/bin/pngquant",
            args: "--speed 1 --force --output %{new_filename} -- %{filename}"
          ],
          jpeg: [
            bin: "/usr/local/bin/cjpeg",
            args: "-quality 90 %{filename} > %{new_filename}"
          ]
        ]

  or

      config :brando, Brando.Images,
        optimize: false

  When uploading images through modules (Image, ImageSeries etc) this gets called automatically.

  If you have a `Brando.ImageField`, you must call `optimize/3` in your context after inserting
  to the database.

      defmodule MyApp.Users do
        alias MyApp.User
        def create(params) do
          user =
            params
            |> User.changeset()
            |> Repo.insert!

          optimize(user, :avatar)
        end
      end

  """

  @doc """
  Optimize `img`

  Checks image for `optimized` flag, gets the image type and sends off
  to `do_optimize`.
  """
  def optimize(%Ecto.Changeset{} = changeset, field_name) do
    case Ecto.Changeset.get_change(changeset, field_name, nil) do
      nil ->
        changeset
      record ->
        optimize(record, field_name)
        changeset
    end
  end
  def optimize(record, field_name) do
    optimize(record, field_name, Map.get(record, field_name))
  end
  def optimize(record, field_name, %Brando.Type.Image{optimized: false} = img_field) do
    field_name_atom = is_binary(field_name) && String.to_atom(field_name) || field_name
    if Map.get(record, field_name_atom).optimized == true do
      {:ok, img_field}
    else
      type = Brando.Images.Utils.image_type(img_field.path)
      case type do
        :jpeg -> do_optimize({:jpeg, img_field, field_name_atom, record})
        :png  -> do_optimize({:png, img_field, field_name_atom, record})
        _     -> {:ok, img_field}
      end
    end
  end

  def optimize(_, _, %Brando.Type.Image{optimized: true} = img_field) do
    {:ok, img_field}
  end

  defp do_optimize(params) do
    #Task.start_link fn ->
      params
      |> run_optimization()
      |> set_optimized_flag()
      |> store()
    #end
  end

  defp run_optimization({type, img_field, field_name, record}) do
    require Logger
    cfg =
      Brando.Images
      |> Brando.config
      |> Keyword.get(:optimize, [])
      |> Keyword.get(type)

    if cfg do
      Enum.map(img_field.sizes, &(Task.async(fn ->
        args = interpolate_and_split_args(elem(&1, 1), cfg[:args])
        System.cmd(cfg[:bin], args)
      end))) |> Enum.map(&Task.await/1)

      {:ok, {type, img_field, field_name, record}}
    else
      {:error, {type, img_field, field_name, record}}
    end
  end

  defp interpolate_and_split_args(file, args) do
    filename =
      file
      |> Brando.Images.Utils.media_path
      |> String.replace(" ", "\\ ")

    newfile =
      file
      |> Brando.Images.Utils.optimized_filename
      |> Brando.Images.Utils.media_path
      |> String.replace(" ", "\\ ")

    args
    |> String.replace("%{filename}", filename)
    |> String.replace("%{new_filename}", newfile)
    |> String.split(" ")
  end

  defp set_optimized_flag({:ok, {type, img_field, field_name, record}}) do
    img_field = Map.put(img_field, :optimized, true)
    {type, img_field, field_name, record}
  end

  defp set_optimized_flag({:error, params}) do
    params
  end

  defp store({_, img_field, field_name, record}) do
    record
    |> Ecto.Changeset.cast(Map.put(%{}, field_name, img_field), [field_name])
    |> Brando.repo.update!
  end
end
