defmodule Brando.Images.Operations.Sizing do
  alias Brando.Images
  alias Brando.Progress

  @doc """
  Create a sized version of image
  """
  def create_image_size(%Images.Operation{
    type: :gif,
    id: id,
    img_field: %{path: image_src, width: width, height: height},
    sized_img_path: image_dest,
    sized_img_dir: image_dest_dir,
    filename: filename,
    size_key: size_key,
    size_cfg: size_cfg,
    user: user
  }) do
    Progress.update_progress(user, "#{filename} — Oppretter bildestørrelse: <strong>#{size_key}</strong>", key: to_string(id) <> size_key)
    File.mkdir_p(image_dest_dir)

    size_cfg = get_size_cfg_orientation(size_cfg, height, width)

    # This is slightly dumb, but should be enough. If we crop, we always pass WxH.
    # If we don't, we always pass W or xH.
    {crop, modifier, size} =
      if size_cfg["crop"] do
        {"--crop 0,0-#{String.replace(size_cfg["size"], "x", ",")}", "--resize", size_cfg["size"]}
      else
        modifier =
          (String.contains?(size_cfg["size"], "x") && "--resize-fit-height") ||
            "--resize-fit-width"

        size = String.replace(size_cfg["size"], ~r/x|\^|\!|\>|\<|\%/, "")
        {"", modifier, size}
      end

    params = ~w(#{crop} #{modifier} #{size} --output #{image_dest} -i #{image_src})

    System.cmd("gifsicle", params, stderr_to_stdout: true)
  end

  def create_image_size(%Images.Operation{
    type: _,
    id: id,
    img_field: %{path: image_src, focal: focal, width: width, height: height},
    filename: filename,
    sized_img_path: image_dest,
    sized_img_dir: image_dest_dir,
    size_key: size_key,
    size_cfg: size_cfg,
    user: user
  }) do
    Progress.update_progress(user, "#{filename} — Oppretter bildestørrelse: <strong>#{size_key}</strong>", key: to_string(id) <> size_key)
    File.mkdir_p(image_dest_dir)

    image_src_path = Images.Utils.media_path(image_src)
    image_dest_path = Images.Utils.media_path(image_dest)

    with true <- File.exists?(image_src_path),
         image <- Mogrify.open(image_src_path) do
      quality = Map.get(size_cfg, "quality", "100")

      size_cfg = get_size_cfg_orientation(size_cfg, height, width)

      if size_cfg["crop"] do
        geometry_with_focal = calculate_geometry_with_focal(focal, width, height, size_cfg)

        image
        |> Mogrify.resize_to_fill(geometry_with_focal)
        |> Mogrify.resize_to_fill(size_cfg["size"])
        |> Mogrify.custom("quality", quality)
        |> Mogrify.save(path: image_dest_path)
      else
        image
        |> Mogrify.resize_to_limit(size_cfg["size"])
        |> Mogrify.custom("quality", quality)
        |> Mogrify.save(path: image_dest_path)
      end

      Progress.update_progress(user, "#{filename} — Oppretter bildestørrelse: <strong>#{size_key}</strong>", key: to_string(id) <> size_key, percent: 100)

      {:ok, %Images.TransformResult{
        id: id,
        size_key: size_key,
        image_path: image_dest
      }}
    else
      false ->
        {:error, {:create_image_size, {:file_not_found, image_src_path}}}
    end
  end

  defp get_size_cfg_orientation(size_cfg, width, height) do
    if Map.has_key?(size_cfg, "portrait") do
      if height > width do
        size_cfg["portrait"]
      else
        size_cfg["landscape"]
      end
    else
      size_cfg
    end
  end

  defp calculate_geometry_with_focal(focal, width, height, size_cfg) do
    focal = %{
      x: focal["x"] / 100 * width,
      y: focal["y"] / 100 * height
    }

    [resize_width, resize_height] =
      size_cfg["size"]
      |> String.replace(~r/\^|\!|\>|\<|\%/, "")
      |> String.split("x")

    k = String.to_integer(resize_width) / String.to_integer(resize_height)

    wm = width
    hm = wm / k

    [hm, wm] =
      if hm > height do
        [height, height * k]
      else
        [hm, wm]
      end

    fx2 = focal.x * wm / width
    fy2 = focal.y * hm / height

    "#{wm}x#{hm}+#{focal.x - fx2}+#{focal.y - fy2}"
  end
end
