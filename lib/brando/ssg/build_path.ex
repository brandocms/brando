defmodule Brando.SSG.BuildPath do
  @moduledoc """
  Where a request path lies in a static build, for whatever serves one: a
  build's preview (`Brando.SSG.PreviewController`) and the installation
  serving a site's published build (`Brando.SSG.LocalDelivery`).

  A path resolves inside the build's directory only. A segment that is empty,
  `.` or `..`, or that holds a slash (an encoded `%2F`), a backslash or a NUL,
  refuses the whole path, and a file reached through a symbolic link is no
  file of the build.
  """

  alias Brando.Sites.Site
  alias Brando.SSG.Builds

  @doc """
  The file a path's decoded segments name, relative to the build's root: a
  segment with an extension names itself, any other path the `index.html` in
  it, and `[]` the root's. `:error` for a path that could leave the root.

      iex> Brando.SSG.BuildPath.relative(["about"])
      {:ok, "about/index.html"}

      iex> Brando.SSG.BuildPath.relative(["feed.xml"])
      {:ok, "feed.xml"}

      iex> Brando.SSG.BuildPath.relative(["..", "etc"])
      :error
  """
  @spec relative([String.t()]) :: {:ok, String.t()} | :error
  def relative([]), do: {:ok, "index.html"}

  def relative(segments) when is_list(segments) do
    with true <- Enum.all?(segments, &plain_segment?/1),
         {:ok, safe_path} <- segments |> Path.join() |> Path.safe_relative() do
      if Path.extname(safe_path) == "",
        do: {:ok, Path.join(safe_path, "index.html")},
        else: {:ok, safe_path}
    else
      _unsafe -> :error
    end
  end

  @doc """
  `relative/1` for a path's segments as they arrive, percent-encoded
  (`conn.path_info`). A malformed escape (`%zz`) is kept as it is, as
  `URI.decode/1` keeps it.
  """
  @spec relative_encoded([String.t()]) :: {:ok, String.t()} | :error
  def relative_encoded(segments) when is_list(segments), do: segments |> Enum.map(&URI.decode/1) |> relative()

  defp plain_segment?(segment) when is_binary(segment),
    do: segment not in ["", ".", ".."] and not String.contains?(segment, ["/", "\\", <<0>>])

  defp plain_segment?(_segment), do: false

  @doc """
  Whether `relative` is a regular file under `root`, reached without a
  symbolic link on the way.
  """
  @spec regular_file?(String.t(), String.t()) :: boolean()
  def regular_file?(root, relative) do
    parts = Path.split(relative)
    {dirs, [_file]} = Enum.split(parts, -1)

    Enum.reduce_while(Enum.with_index(parts), root, fn {part, index}, path ->
      path = Path.join(path, part)
      expected = if index < length(dirs), do: :directory, else: :regular

      case File.lstat(path) do
        {:ok, %{type: ^expected}} -> {:cont, path}
        _other -> {:halt, false}
      end
    end) != false
  end

  @doc "Whether a build's directory is one of `site`'s, directly under its build root."
  @spec managed?(String.t(), Site.t()) :: boolean()
  def managed?(build_path, %Site{} = site),
    do: Path.dirname(Path.expand(build_path)) == Path.expand(Builds.build_root(site))
end
