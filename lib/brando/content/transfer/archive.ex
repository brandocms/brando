defmodule Brando.Content.Transfer.Archive do
  use Gettext, backend: Brando.Gettext
  @moduledoc "Bounded, checksummed ZIP transport for saved block-field content and media originals."

  require Record
  Record.defrecordp(:zip_file, Record.extract(:zip_file, from_lib: "stdlib/include/zip.hrl"))
  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  alias Brando.Content.Definition.{Error, Value}
  alias Brando.Content.Transfer.Error, as: TransferError

  @max_bytes 128_000_000
  @max_expanded_bytes 256_000_000
  @max_files 2_000
  @manifest_bytes 8_000_000

  def max_bytes, do: @max_bytes

  def export(bundle, media \\ []) do
    files = Map.new(media)
    manifest = Jason.encode!(bundle, pretty: true)

    if byte_size(manifest) > @manifest_bytes do
      {:error, dgettext("content_transfer", "Content manifest exceeds 8 MB. Export fewer fields.")}
    else
      pack(Map.put(files, "content.json", manifest))
    end
  end

  def read(binary) when is_binary(binary) do
    TransferError.protect(fn ->
      files = unpack!(binary)

      json =
        files["content.json"] ||
          Error.raise!("ZIP", dgettext("content_transfer", "content.json is missing; choose a content transfer bundle"))

      if byte_size(json) > @manifest_bytes,
        do: Error.raise!("content.json", dgettext("content_transfer", "manifest exceeds 8 MB"))

      bundle =
        case Jason.decode(json) do
          {:ok, bundle} when is_map(bundle) -> bundle
          _ -> Error.raise!("content.json", dgettext("content_transfer", "expected a JSON object"))
        end

      Brando.Content.Transfer.Portable.validate!(bundle)

      Enum.each(bundle["dependencies"], fn {_token, dependency} ->
        if asset = dependency["original"] do
          body =
            files[asset["path"]] || Error.raise!("media", dgettext("content_transfer", "a bundled original is missing"))

          unless byte_size(body) == asset["bytes"] && checksum(body) == asset["sha256"],
            do: Error.raise!("media", dgettext("content_transfer", "original checksum or size does not match"))
        end
      end)

      %{bundle: bundle, files: Map.delete(files, "content.json")}
    end)
  rescue
    _ in [KeyError, BadMapError, FunctionClauseError, Protocol.UndefinedError, ArgumentError, CaseClauseError, MatchError] ->
      {:error, dgettext("content_transfer", "The content manifest is malformed. Export a fresh bundle from the source.")}
  end

  def checksum(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  @doc false
  def pack(files) do
    TransferError.protect(fn ->
      validate_sizes!(Enum.map(files, fn {_name, body} -> byte_size(body) end))
      entries = files |> Enum.sort() |> Enum.map(fn {name, body} -> {String.to_charlist(name), body} end)

      case :zip.create(~c"content.zip", entries, [:memory]) do
        {:ok, {_, binary}} when byte_size(binary) <= @max_bytes ->
          binary

        {:ok, _} ->
          Error.raise!("ZIP", dgettext("content_transfer", "compressed bundle exceeds 128 MB; export fewer fields"))

        {:error, _} ->
          Error.raise!("ZIP", dgettext("content_transfer", "could not create the bundle"))
      end
    end)
  end

  defp unpack!(binary) do
    if byte_size(binary) > @max_bytes, do: Error.raise!("ZIP", dgettext("content_transfer", "file exceeds 128 MB"))

    table =
      case :zip.table(binary) do
        {:ok, table} -> table
        {:error, _} -> Error.raise!("ZIP", dgettext("content_transfer", "expected a valid ZIP archive"))
      end

    entries = for zip_file() = entry <- table, do: entry
    if length(entries) > @max_files, do: Error.raise!("ZIP", dgettext("content_transfer", "bundle exceeds 2,000 entries"))

    files =
      Enum.flat_map(entries, fn zip_file(name: name, info: info, offset: offset) = entry ->
        name = List.to_string(name)
        validate_local_name!(binary, offset, name)
        validate_path!(String.trim_trailing(name, "/"))

        cond do
          file_info(info, :type) == :directory ->
            []

          file_info(info, :type) != :regular ->
            Error.raise!("ZIP", dgettext("content_transfer", "only regular files are supported"))

          ignored?(name) ->
            []

          true ->
            [{name, entry}]
        end
      end)

    Value.unique!(Enum.map(files, &elem(&1, 0)), "ZIP filenames")
    validate_sizes!(Enum.map(files, fn {_, entry} -> file_info(zip_file(entry, :info), :size) end))
    Enum.each(files, fn {_, entry} -> validate_expansion!(binary, entry) end)
    names = Enum.map(files, fn {name, _} -> String.to_charlist(name) end)

    extracted =
      case :zip.extract(binary, [:memory, {:file_list, names}]) do
        {:ok, extracted} -> extracted
        {:error, _} -> Error.raise!("ZIP", dgettext("content_transfer", "could not read the archive"))
      end

    files = Enum.map(extracted, fn {name, body} -> {List.to_string(name), body} end)
    validate_sizes!(Enum.map(files, fn {_name, body} -> byte_size(body) end))
    files = unwrap_directory(files)

    Enum.each(files, fn {name, _} ->
      validate_path!(name)

      unless name == "content.json" or Regex.match?(~r/^media\/[a-f0-9]{64}$/, name),
        do:
          Error.raise!(
            name,
            dgettext("content_transfer", "bundle may contain only content.json and checksummed media originals")
          )
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
        if MapSet.member?(filenames, parent),
          do: Error.raise!(name, dgettext("content_transfer", "file and directory paths overlap"))
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
      Error.raise!("ZIP", dgettext("content_transfer", "unsafe archive path"))
    end
  end

  # OTP sanitizes absolute names when listing ZIPs. Check the original local
  # header as well, so those names are rejected instead of silently renamed.
  defp validate_local_name!(binary, offset, name) do
    if offset < 0 or offset + 30 > byte_size(binary),
      do: Error.raise!("ZIP", dgettext("content_transfer", "invalid file header"))

    case binary_part(binary, offset, 30) do
      <<"PK", 3, 4, _::binary-size(22), length::little-16, _extra::little-16>>
      when offset + 30 + length <= byte_size(binary) ->
        original = binary_part(binary, offset + 30, length)
        validate_path!(String.trim_trailing(original, "/"))
        if original != name, do: Error.raise!("ZIP", dgettext("content_transfer", "inconsistent archive filenames"))

      _ ->
        Error.raise!("ZIP", dgettext("content_transfer", "invalid file header"))
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
           do: Error.raise!("ZIP", dgettext("content_transfer", "unsupported compression or inconsistent file sizes"))

    if method == 0 do
      if compressed != expanded, do: Error.raise!("ZIP", dgettext("content_transfer", "inconsistent file sizes"))
    else
      stream = :zlib.open()

      try do
        :ok = :zlib.inflateInit(stream, -15)
        validate_chunks!(stream, binary_part(binary, start, compressed), expanded)
        :ok = :zlib.inflateEnd(stream)
      rescue
        _ in [ErlangError, ArgumentError] ->
          Error.raise!("ZIP", dgettext("content_transfer", "invalid compressed content"))
      after
        :zlib.close(stream)
      end
    end
  end

  defp validate_chunks!(stream, input, remaining) do
    {status, output} = :zlib.safeInflate(stream, input)
    remaining = remaining - IO.iodata_length(output)
    if remaining < 0, do: Error.raise!("ZIP", dgettext("content_transfer", "expanded content exceeds its declared size"))

    case status do
      :continue -> validate_chunks!(stream, [], remaining)
      :finished when remaining == 0 -> :ok
      _ -> Error.raise!("ZIP", dgettext("content_transfer", "inconsistent expanded content size"))
    end
  end

  defp validate_sizes!(sizes) do
    if length(sizes) > @max_files or Enum.any?(sizes, &(not is_integer(&1) or &1 < 0)) or
         Enum.sum(sizes) > @max_expanded_bytes,
       do: Error.raise!("ZIP", dgettext("content_transfer", "bundle exceeds 2,000 files or 256 MB of expanded content"))
  end
end
