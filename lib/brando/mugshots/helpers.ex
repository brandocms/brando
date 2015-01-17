defmodule Brando.Mugshots.Helpers do
  import Brando.Mugshots.Utils
  def img(file, size) do
    {file_path, filename} = split_path(file)
    Path.join([file_path, Atom.to_string(size), filename])
  end
end