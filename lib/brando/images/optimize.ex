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

  """

  @doc """
  Optimize `img`

  Checks image for `optimized` flag, gets the image type and sends off
  to `do_optimize/2`.
  """
  def optimize(%Brando.Type.Image{optimized: false} = img_field, field_name, schema, data) do
    type = Brando.Images.Utils.image_type(img_field.path)
    case type do
      :jpeg -> do_optimize({:jpeg, img_field, field_name, schema, data})
      :png  -> do_optimize({:png, img_field, field_name, schema, data})
      _     -> {:ok, img_field}
    end
  end

  def optimize(%Brando.Type.Image{optimized: true} = img_field, _, _, _) do
    {:ok, img_field}
  end

  defp do_optimize(params) do
    Task.start fn ->
      params
      |> run_optimization()
      |> set_optimized_flag()
      |> store()
    end
  end

  defp run_optimization({type, img_field, field_name, schema, data}) do
    cfg =
      Brando.Images
      |> Brando.config
      |> Keyword.get(:optimize, [])
      |> Keyword.get(type)

    if cfg do
      for file <- Enum.map(img_field.sizes, &elem(&1, 1)) do
        args = interpolate_and_split_args(file, cfg[:args])
        System.cmd cfg[:bin], args
      end
      {:ok, {type, img_field, field_name, schema, data}}
    else
      {:error, {type, img_field, field_name, schema, data}}
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

  defp set_optimized_flag({:ok, {type, img_field, field_name, schema, data}}) do
    img_field = Map.put(img_field, :optimized, true)
    {type, img_field, field_name, schema, data}
  end

  defp set_optimized_flag({:error, params}) do
    params
  end

  defp store({type, img_field, field_name, schema, data}) do
    field_name_atom = is_binary(field_name) && String.to_atom(field_name) || field_name

    data
    |> Ecto.Changeset.cast(Map.put(%{}, field_name_atom, img_field), [field_name_atom])
    |> Brando.repo.update!
  end
end
