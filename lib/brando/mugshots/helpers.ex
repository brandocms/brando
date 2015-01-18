defmodule Brando.Mugshots.Helpers do
  @moduledoc """
  View helpers for the Mugshots module
  """
  import Brando.Mugshots.Utils

  @doc """
  View helper wrapper for `Brando.Mugshots.Utils.size_dir/2`
  Inserts the `size` into `file`, returning the path to the image
  """
  def img(file, size), do: size_dir(file, size)
end