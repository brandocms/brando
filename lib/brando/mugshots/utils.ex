defmodule Brando.Mugshots.Utils do
  require Logger
  def split_path(file) do
    filename = Path.split(file)
    |> List.last
    path = Path.split(file)
    |> List.delete_at(-1)
    |> Path.join
    {path, filename}
  end

  def size_dir(file, size) do
    {path, filename} = split_path(file)
    Path.join([path, size, filename])
  end

  def get_media_abspath do
    Path.join([Mix.Project.app_path, "priv", "media"])
  end

end