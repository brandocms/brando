defmodule Brando.Content.Definition.Archive do
  @moduledoc "ZIP transport for editable module definitions, templates and their baseline."

  require Record
  Record.defrecordp(:zip_file, Record.extract(:zip_file, from_lib: "stdlib/include/zip.hrl"))
  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  alias Brando.Content.Definition.{Error, Value, Writer}
  alias Brando.Content.Definitions

  @max_bytes 5_000_000
  @max_expanded_bytes 20_000_000
  @max_files 500

  def max_bytes, do: @max_bytes

  @doc "Exports authorized local definitions as a ZIP binary."
  def export(actor, opts \\ []) do
    with_directory(fn root ->
      with {:ok, exported} <- Definitions.export(Path.join(root, "modules"), actor, opts),
           {:ok, binary} <- pack(Writer.files(exported.bundle)) do
        {:ok, %{binary: binary, count: length(exported.bundle["modules"])}}
      end
    end)
  end

  @doc "Reads a bounded ZIP without extracting archive paths directly to disk."
  def read(binary) when is_binary(binary) do
    with {:ok, files} <- Definitions.protect(fn -> unpack!(binary) end) do
      with_directory(fn root ->
        Enum.each(files, fn {name, body} ->
          path = Path.join(root, name)
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, body, [:exclusive])
        end)

        with {:ok, bundle} <- Definitions.read(root), do: {:ok, %{bundle: bundle, files: files}}
      end)
    end
  end

  @doc "Updates only the archive's baseline; authored source and comments remain intact."
  def update(%{files: files}, bundle) do
    lock = bundle |> Map.take(~w(format_version source baseline references)) |> Jason.encode!(pretty: true)
    pack(Map.put(files, "modules.lock.json", lock <> "\n"))
  end

  @doc false
  def pack(files) do
    Definitions.protect(fn ->
      validate_sizes!(Enum.map(files, fn {_name, body} -> byte_size(body) end))
      entries = files |> Enum.sort() |> Enum.map(fn {name, body} -> {String.to_charlist(name), body} end)

      case :zip.create(~c"modules.zip", entries, [:memory]) do
        {:ok, {_, binary}} when byte_size(binary) <= @max_bytes -> binary
        {:ok, _} -> Error.raise!("ZIP", "compressed bundle exceeds 5 MB; export fewer modules")
        {:error, _} -> Error.raise!("ZIP", "could not create the bundle")
      end
    end)
  end

  defp unpack!(binary) do
    if byte_size(binary) > @max_bytes, do: Error.raise!("ZIP", "file exceeds 5 MB")

    table =
      case :zip.table(binary) do
        {:ok, table} -> table
        {:error, _} -> Error.raise!("ZIP", "expected a valid ZIP archive")
      end

    entries = for zip_file() = entry <- table, do: entry
    if length(entries) > @max_files, do: Error.raise!("ZIP", "bundle exceeds 500 entries")

    files =
      Enum.flat_map(entries, fn zip_file(name: name, info: info, offset: offset) = entry ->
        name = List.to_string(name)
        validate_local_name!(binary, offset, name)
        validate_path!(String.trim_trailing(name, "/"))

        cond do
          file_info(info, :type) == :directory -> []
          file_info(info, :type) != :regular -> Error.raise!("ZIP", "only regular files are supported")
          ignored?(name) -> []
          true -> [{name, entry}]
        end
      end)

    Value.unique!(Enum.map(files, &elem(&1, 0)), "ZIP filenames")
    validate_sizes!(Enum.map(files, fn {_, entry} -> file_info(zip_file(entry, :info), :size) end))
    Enum.each(files, fn {_, entry} -> validate_expansion!(binary, entry) end)
    names = Enum.map(files, fn {name, _} -> String.to_charlist(name) end)

    extracted =
      case :zip.extract(binary, [:memory, {:file_list, names}]) do
        {:ok, extracted} -> extracted
        {:error, _} -> Error.raise!("ZIP", "could not read the archive")
      end

    files = Enum.map(extracted, fn {name, body} -> {List.to_string(name), body} end)
    validate_sizes!(Enum.map(files, fn {_name, body} -> byte_size(body) end))
    files = unwrap_directory(files)

    Enum.each(files, fn {name, _} ->
      validate_path!(name)

      unless Path.extname(name) in ~w(.exs .heex .liquid) or name == "modules.lock.json",
        do: Error.raise!(name, "bundle may contain only DSL, HEEx, Liquid and modules.lock.json files")
    end)

    # Files are written by us, never by ZIP extraction. Prefix collisions are
    # rejected before any write, including a file used as another file's parent.
    filenames = MapSet.new(Enum.map(files, &elem(&1, 0)))

    Enum.each(filenames, fn name ->
      name
      |> Path.split()
      |> Enum.drop(-1)
      |> Enum.scan(&Path.join(&2, &1))
      |> Enum.each(fn parent ->
        if MapSet.member?(filenames, parent), do: Error.raise!(name, "file and directory paths overlap")
      end)
    end)

    Map.new(files)
  end

  defp unwrap_directory(files) do
    case files |> Enum.map(fn {name, _} -> hd(Path.split(name)) end) |> Enum.uniq() do
      [directory] ->
        if Enum.all?(files, fn {name, _} -> String.starts_with?(name, directory <> "/") end),
          do: Enum.map(files, fn {name, body} -> {String.replace_prefix(name, directory <> "/", ""), body} end),
          else: files

      _ ->
        files
    end
  end

  defp validate_path!(name) do
    if name == "" or Path.type(name) != :relative or String.contains?(name, ["\\", ":", <<0>>]) or
         Enum.any?(String.split(name, "/"), &(&1 in ["", ".", ".."])) do
      Error.raise!("ZIP", "unsafe archive path")
    end
  end

  # OTP sanitizes absolute names when listing ZIPs. Check the original local
  # header as well, so those names are rejected instead of silently renamed.
  defp validate_local_name!(binary, offset, name) do
    if offset < 0 or offset + 30 > byte_size(binary), do: Error.raise!("ZIP", "invalid file header")

    case binary_part(binary, offset, 30) do
      <<"PK", 3, 4, _::binary-size(22), length::little-16, _extra::little-16>>
      when offset + 30 + length <= byte_size(binary) ->
        original = binary_part(binary, offset + 30, length)
        validate_path!(String.trim_trailing(original, "/"))
        if original != name, do: Error.raise!("ZIP", "inconsistent archive filenames")

      _ ->
        Error.raise!("ZIP", "invalid file header")
    end
  end

  defp ignored?(name), do: String.starts_with?(name, "__MACOSX/") or Path.basename(name) == ".DS_Store"

  # ZIP size metadata is untrusted. Bound actual inflation before letting OTP
  # allocate complete files, and require consistent local/central size headers.
  defp validate_expansion!(binary, zip_file(offset: offset, comp_size: compressed, info: info)) do
    <<_::binary-size(6), flags::little-16, method::little-16, _::binary-size(8), local_compressed::little-32,
      local_expanded::little-32, name_length::little-16, extra_length::little-16>> = binary_part(binary, offset, 30)

    expanded = file_info(info, :size)
    start = offset + 30 + name_length + extra_length
    descriptor? = Bitwise.band(flags, 8) != 0

    unless Bitwise.band(flags, 1) == 0 and method in [0, 8] and start + compressed <= byte_size(binary) and
             (descriptor? or (local_compressed == compressed and local_expanded == expanded)),
           do: Error.raise!("ZIP", "unsupported compression or inconsistent file sizes")

    if method == 0 do
      if compressed != expanded, do: Error.raise!("ZIP", "inconsistent file sizes")
    else
      stream = :zlib.open()

      try do
        :ok = :zlib.inflateInit(stream, -15)
        validate_chunks!(stream, binary_part(binary, start, compressed), expanded)
        :ok = :zlib.inflateEnd(stream)
      rescue
        _ in [ErlangError, ArgumentError] -> Error.raise!("ZIP", "invalid compressed content")
      after
        :zlib.close(stream)
      end
    end
  end

  defp validate_chunks!(stream, input, remaining) do
    {status, output} = :zlib.safeInflate(stream, input)
    remaining = remaining - IO.iodata_length(output)
    if remaining < 0, do: Error.raise!("ZIP", "expanded content exceeds its declared size")

    case status do
      :continue -> validate_chunks!(stream, [], remaining)
      :finished when remaining == 0 -> :ok
      _ -> Error.raise!("ZIP", "inconsistent expanded content size")
    end
  end

  defp validate_sizes!(sizes) do
    if length(sizes) > @max_files or Enum.any?(sizes, &(not is_integer(&1) or &1 < 0)) or
         Enum.sum(sizes) > @max_expanded_bytes,
       do: Error.raise!("ZIP", "bundle exceeds 500 files or 20 MB of expanded content")
  end

  defp with_directory(fun) do
    root = Path.join(System.tmp_dir!(), "brando-module-files-" <> Base.url_encode64(:crypto.strong_rand_bytes(18)))

    case Definitions.protect(fn ->
           File.mkdir!(root)

           try do
             fun.(root)
           after
             File.rm_rf(root)
           end
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
