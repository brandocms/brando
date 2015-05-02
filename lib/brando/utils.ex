defmodule Brando.Utils do
  @moduledoc """
  Assorted utility functions.
  """

  require Logger

  @doc """
  Converts `string` to an ascii slug. Removes all unicode, spaces,
  extraneous dashes and punctuation and downcases the slug
  """
  @spec slugify(String.t) :: String.t
  def slugify(string), do:
    Slugger.slugify_downcase(string)

  @doc """
  Converts `filename` to an ascii slug, as per slugify/1.
  This function retains the extension of the filename, only converting
  the basename.

  ## Example

        iex(1)> slugify_filename("test with spaces.jpeg")
        "test-with-spaces.jpeg"

  """
  def slugify_filename(filename) do
    {basename, ext} = split_filename(filename)
    slugged_filename = slugify(basename)
    "#{slugged_filename}#{ext}"
  end

  @doc """
  Generates a random basename for `filename`.
  Keeps the original extension.
  """
  def random_filename(filename) do
    ext = Path.extname(filename)
    rnd_basename =
      ({filename, :erlang.now}
      |> :erlang.phash2
      |> Integer.to_string(32)
      |> String.downcase) <>
      ({:erlang.now, filename}
      |> :erlang.phash2
      |> Integer.to_string(32)
      |> String.downcase)
    "#{rnd_basename}#{ext}"
  end

  @doc """
  Adds an unique postfix to `filename`
  """
  def unique_filename(filename) do
    ext = Path.extname(filename)
    base = String.replace(filename, ext, "")
    rnd_basename =
      {filename, :erlang.now}
      |> :erlang.phash2
      |> Integer.to_string(32)
      |> String.downcase
    "#{base}-#{rnd_basename}#{ext}"
  end

  @doc """
  Splits `file` (a path and filename).
  Return {`path`, `filename`}

  ## Example

      iex> split_path("test/dir/filename.jpg")
      {"test/dir", "filename.jpg"}
  """
  def split_path(file) do
    case String.contains?(file, "/") do
      true ->
        filename = Path.split(file) |> List.last
        path = Path.split(file)
        |> List.delete_at(-1)
        |> Path.join
        {path, filename}
      false ->
        {"", file}
    end
  end

  @doc """
  Splits `filename` into `basename` and `extension`
  Return {`basename`, `ext`}

  ## Example

      iex> split_filename("filename.jpg")
      {"filename", ".jpg"}
  """
  def split_filename(filename) do
    ext = Path.extname(filename)
    basename = Path.basename(filename, ext)
    {basename, ext}
  end

  @doc """
  Converts `coll` (if it's a struct) to a map with string keys
  """
  def to_string_map(nil), do: nil
  def to_string_map(coll) do
    case Map.has_key?(coll, :__struct__) do
      true ->
        Map.delete(coll, :__struct__)
        |> Enum.map(fn({k, v}) -> {Atom.to_string(k), v} end)
        |> Enum.into(%{})
      false -> coll
    end
  end

  @doc """
  Maybe implementation. If `arg1` is nil, do nothing.
  Else, invoke `fun` on `item`.
  """
  def maybe(nil, _fun), do: nil
  def maybe(item, fun), do: fun.(item)

  @doc """
  Converts an ecto datetime record to ISO 8601 format.
  """
  @spec to_iso8601(Ecto.DateTime.t) :: String.t
  def to_iso8601(dt) do
    list = [dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec]
    :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", list)
    |> IO.iodata_to_binary
  end
end