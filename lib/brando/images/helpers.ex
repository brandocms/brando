defmodule Brando.Images.Helpers do
  @moduledoc """
  View helpers for the Images module
  """
  import Brando.Images.Utils

  @doc """
  View helper wrapper for `Brando.Images.Utils.size_dir/2`
  Inserts the `size` into `file`, returning the path to the image.
  If `file` is nil, use `default` instead.
  """
  def _img(file, size, default \\ nil)
  def _img(nil, size, default) do
    size_dir(default, size)
  end
  def _img(file, size, _default) do
    size_dir(file, size)
  end

  @doc """
  Grabs `size` from the `image_field` json struct.
  If default is passed, return size_dir of `default`.
  Returns path to image.
  """
  def img(image_field, size, default \\ nil)
  def img(nil, size, default) do
    size_dir(default, size)
  end
  def img(image_field, size, _default) when is_binary(size) do
    image_field.sizes[String.to_atom(size)]
  end
  def img(image_field, size, _default) when is_atom(size) do
    image_field.sizes[size]
  end
end