defmodule Brando.Mugshots.Utils do
  @moduledoc """
  General utilities pertaining to the Mugshots module
  """

  import Brando.Utils

  @doc """
  Splits `file` with `split_path/1`, adds `size` to the path before
  concatenating it with the filename.

  ## Example

      iex> size_dir("test/dir/filename.jpg", :thumb)
      "test/dir/thumb/filename.jpg"

  """
  def size_dir(file, size) when is_binary(size) do
    {path, filename} = split_path(file)
    Path.join([path, size, filename])
  end

  def size_dir(file, size) when is_atom(size) do
    {path, filename} = split_path(file)
    Path.join([path, Atom.to_string(size), filename])
  end

  @doc """
  Returns the media absolute path by concatenating
  `Mix.Project.app_path` with `priv/media`
  """
  def get_media_abspath do
    if Mix.env == :test do
      Path.join([Mix.Project.app_path, "tmp", "media"])
    else
      Path.join([Mix.Project.app_path, "priv", "media"])
    end
  end

end