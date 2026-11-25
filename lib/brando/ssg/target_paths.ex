defmodule Brando.SSG.TargetPaths do
  @moduledoc """
  The paths of an rsync deploy's target, as `Brando.SSG.TargetReview` reads
  and writes them, with no I/O but the walk of a build: relative to the
  target, no leading `/`, a directory's ending in `/`.

  `plan/3` is the one place a deploy's file list and filter rules are made.
  The rules are rsync filter rules, one per NUL (`--from0`), first match
  wins: the keep list's paths are protected (`P`), the deletable ones are at
  risk (`R`), and every other path is protected (`P *`), so the receiving
  rsync deletes nothing else, also a file that appears there during the
  run. A name matches only itself: one with a wildcard character has each of
  `\\ * ? [` escaped, as rsync reads a backslash as an escape only in a
  pattern with a wildcard, and a newline is an ordinary character in a
  NUL-separated file.

  `parse_listing/2` reads the `*deleting` lines of a dry run made with
  `listing_format/1`, which starts each line rsync itself writes with a
  nonce the remote host never sees, so a line the host writes cannot pass
  for one.
  """

  @typedoc "A path on the target: relative, a directory's ending in `/`."
  @type path :: String.t()

  @typedoc """
  What a deploy uploads and what its run may delete, with the rules that
  say so to the receiving rsync.
  """
  @type plan :: %{upload: [path()], deletable: [path()], rules: iodata()}

  @doc """
  A deploy of the build at `build_path`: its paths, the paths the receiver
  may delete (`deletable`, those Brando uploaded or an admin confirmed, less
  what `keep` covers) and the filter rules that let it delete only those.
  The build's files at the `hidden` paths are not sent (`H`, which the
  receiver does not read: the target's file of that name is deleted when it
  is deletable).
  """
  @spec plan(String.t(), [path()], [path()], [path()]) :: plan()
  def plan(build_path, deletable, keep, hidden \\ []) do
    deletable = deletable |> Enum.reject(&kept?(&1, keep)) |> Enum.filter(&rule_path?/1) |> Enum.uniq() |> Enum.sort()

    %{
      upload: build_path |> build_paths() |> Enum.reject(&(&1 in hidden)),
      deletable: deletable,
      rules: [
        Enum.map(hidden, &rule("H", pattern(&1, ""))),
        keep_rules(keep),
        Enum.map(deletable, &rule("R", pattern(&1, ""))),
        rule("P", "*")
      ]
    }
  end

  @doc """
  A rule that protects `path` (`:protect`), lets the receiver delete it
  (`:delete`) or keeps the sender from sending it (`:hide`), to put before a
  plan's rules, which it then overrides.
  """
  @spec path_rule(:protect | :delete | :hide, path()) :: iodata()
  def path_rule(:protect, path), do: rule("P", pattern(path, ""))
  def path_rule(:hide, path), do: rule("H", pattern(path, ""))
  def path_rule(:delete, path), do: rule("R", pattern(path, ""))

  @doc "Rules that protect what `keep` covers (`kept?/2`) and nothing else."
  @spec keep_rules([path()]) :: iodata()
  def keep_rules(keep) do
    Enum.map(keep, fn entry ->
      if directory?(entry),
        do: rule("P", pattern(entry, "***")),
        else: [rule("P", pattern(entry, "")), rule("P", pattern(entry <> "/", "***"))]
    end)
  end

  defp rule(kind, pattern), do: [kind, " ", pattern, 0]

  # Anchored at the target's root. A wildcard of our own (`***`) makes rsync
  # read backslashes in the whole pattern as escapes.
  defp pattern(path, suffix) do
    name = if suffix != "" or wildcard?(path), do: escape(path), else: path
    ["/", name, suffix]
  end

  defp wildcard?(path), do: :binary.match(path, ["*", "?", "["]) != :nomatch

  defp escape(path), do: for(<<byte <- path>>, into: "", do: escape_byte(byte))

  defp escape_byte(byte) when byte in ~c"\\*?[", do: <<?\\, byte>>
  defp escape_byte(byte), do: <<byte>>

  @doc "The build's paths, sorted; links are paths, not followed."
  @spec build_paths(String.t()) :: [path()]
  def build_paths(build_path), do: build_path |> walk("") |> Enum.sort()

  defp walk(root, relative) do
    root
    |> Path.join(relative)
    |> File.ls!()
    |> Enum.flat_map(fn name ->
      path = relative <> name

      case File.lstat(Path.join(root, path)) do
        {:ok, %File.Stat{type: :directory}} -> [path <> "/" | walk(root, path <> "/")]
        {:ok, %File.Stat{}} -> [path]
        {:error, _reason} -> []
      end
    end)
  end

  @doc """
  Whether `keep` covers `path`: an entry covers its path and everything
  under it, and one without a trailing `/` also a file of its name.
  """
  @spec kept?(path(), [path()]) :: boolean()
  def kept?(path, keep) do
    Enum.any?(keep, fn entry ->
      if directory?(entry),
        do: String.starts_with?(path, entry),
        else: path == entry or String.starts_with?(path, entry <> "/")
    end)
  end

  @doc "Whether `path` names a directory."
  @spec directory?(path()) :: boolean()
  def directory?(path), do: String.ends_with?(path, "/")

  @doc """
  Whether a path read from the target may become a rule: segments that are
  neither empty nor `.` or `..`, and no NUL.
  """
  @spec rule_path?(path()) :: boolean()
  def rule_path?(path) when is_binary(path) do
    segments = path |> String.replace_suffix("/", "") |> String.split("/")
    path != "" and not String.contains?(path, <<0>>) and Enum.all?(segments, &(&1 not in ["", ".", ".."]))
  end

  @doc """
  Whether `entry` may be on the keep list: relative, segments of letters,
  digits, `. _ ~ + @ , -` and spaces inside them, no `.` or `..` segment,
  a trailing `/` for a directory, at most 255 bytes.
  """
  @spec keep_entry?(term()) :: boolean()
  def keep_entry?(entry) when is_binary(entry) and byte_size(entry) in 1..255 do
    entry
    |> String.replace_suffix("/", "")
    |> String.split("/")
    |> Enum.all?(
      &(&1 not in [".", ".."] and
          Regex.match?(~r/\A[\p{L}\p{N}._~+@,-](?:[\p{L}\p{N}._~+@, -]*[\p{L}\p{N}._~+@,-])?\z/u, &1))
    )
  end

  def keep_entry?(_entry), do: false

  @doc """
  rsync's `--out-format` for a listing whose lines start with `nonce`, read
  back by `parse_listing/2`.
  """
  @spec listing_format(String.t()) :: String.t()
  def listing_format(nonce), do: "--out-format=#{nonce} %i|%n"

  @doc "A nonce for `listing_format/1`."
  @spec nonce() :: String.t()
  def nonce, do: Base.encode16(:crypto.strong_rand_bytes(12))

  @doc """
  The paths of the `*deleting` lines in rsync's output, written with
  `listing_format(nonce)`, with rsync's escapes (`\\#ooo`) decoded. Other
  lines are left out.
  """
  @spec parse_listing(binary(), String.t()) :: [path()]
  def parse_listing(output, nonce) do
    prefix = nonce <> " "

    for line <- String.split(output, "\n"),
        String.starts_with?(line, prefix),
        [item, name] <- [:binary.split(binary_part(line, byte_size(prefix), byte_size(line) - byte_size(prefix)), "|")],
        String.trim(item) == "*deleting",
        do: decode(name)
  end

  # rsync writes a byte it will not print, and a backslash that would read
  # as an escape, as `\#` and three octal digits
  defp decode(name),
    do: Regex.replace(~r/\\#([0-3][0-7]{2})/, name, fn _match, octal -> <<String.to_integer(octal, 8)>> end)

  @doc """
  The top-level entries of `paths`, as the Publishing screen shows them:
  the name (a directory's ending in `/`), how many files are in it (1 for a
  file), and whether `keep` covers it.
  """
  @spec top_level([path()], [path()]) :: [%{name: path(), files: non_neg_integer(), kept: boolean()}]
  def top_level(paths, keep) do
    paths
    |> Enum.group_by(&top/1)
    |> Enum.map(fn {name, paths} ->
      %{name: name, files: Enum.count(paths, &(not directory?(&1))), kept: kept?(name, keep)}
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc "The top-level entry `path` is in."
  @spec top(path()) :: path()
  def top(path) do
    case :binary.split(path, "/") do
      [name, _rest] -> name <> "/"
      [name] -> name
    end
  end

  @doc "A digest of what a listing says, for the screen to name the one it showed."
  @spec digest(term()) :: String.t()
  def digest(term), do: :sha256 |> :crypto.hash(:erlang.term_to_binary(term)) |> Base.encode16(case: :lower)
end
