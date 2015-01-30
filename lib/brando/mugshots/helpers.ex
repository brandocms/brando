defmodule Brando.Mugshots.Helpers do
  @moduledoc """
  View helpers for the Mugshots module
  """
  import Brando.Mugshots.Utils

  @doc """
  View helper wrapper for `Brando.Mugshots.Utils.size_dir/2`
  Inserts the `size` into `file`, returning the path to the image.
  If `file` is nil, use `default` instead.
  """
  def img(file, size, default \\ nil)
  def img(nil, size, default) do
    size_dir(default, size)
  end
  def img(file, size, _default) do
    size_dir(file, size)
  end
end