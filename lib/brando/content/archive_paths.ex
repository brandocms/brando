defmodule Brando.Content.ArchivePaths do
  @moduledoc """
  Path handling shared by the module-definition and content-transfer ZIP readers.

  Both readers validate untrusted archives with their own limits and messages;
  only the path rules that carry no message live here.
  """

  @doc """
  Strips a single top-level directory that every file sits in, as produced when
  an archive is created by zipping a folder. Any other layout is returned as is.
  """
  def unwrap_directory(files) do
    case files |> Enum.map(fn {name, _} -> hd(Path.split(name)) end) |> Enum.uniq() do
      [directory] ->
        if Enum.all?(files, fn {name, _} -> String.starts_with?(name, directory <> "/") end),
          do: Enum.map(files, fn {name, body} -> {String.replace_prefix(name, directory <> "/", ""), body} end),
          else: files

      _ ->
        files
    end
  end

  @doc "True for the metadata entries macOS adds when it creates an archive."
  def ignored?(name), do: String.starts_with?(name, "__MACOSX/") or Path.basename(name) == ".DS_Store"
end
