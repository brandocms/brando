defmodule Brando.SSG.TargetHtaccess do
  @moduledoc """
  The `.htaccess` step of an rsync deploy (`Brando.SSG.TargetReview.deploy/4`)
  to an Apache or LiteSpeed host: the site's `:htaccess` option on
  `Brando.Sites.DeployConfig`, read when the deploy runs, never from the
  build's snapshot.

  The file is the host's and the block between `# BEGIN Brando` and
  `# END Brando` is Brando's (`Brando.SSG.Htaccess`). As the last step before
  the real run, the target's live `.htaccess` is fetched and merged, and the
  merged file is sent in that run, ahead of the build's files: rsync keeps
  the first of two files of one name, so a `.htaccess` of the build's own is
  not sent; when the target's file is the merge already, nothing is sent and
  the build's own is hidden from the sender. The merged file is protected on the target and never on the
  uploaded list. With the option, `_redirects.json` is hidden from the
  sender, so the one an earlier deploy uploaded is deleted.

  With the option off, a target whose state says a block was written
  (`:block`) has the block removed, its other lines kept, and the file
  deleted when nothing else is left in it, unless the keep list holds it
  (then it is left empty). A build with a `.htaccess` of its own replaces
  the host's file as any other file, as it would without the option.

  The deploy stops, with nothing copied, when the fetch fails for another
  reason than there being no file, when the file, or the file with Brando's
  block, is larger than 256 KB, when it is not a file, and when a
  `# BEGIN Brando` has no `# END Brando` after it: Brando never uploads a
  file it could not merge, or could not fetch again.
  """

  alias Brando.Sites.DeployConfig
  alias Brando.Sites.Site
  alias Brando.SSG.Build
  alias Brando.SSG.Htaccess
  alias Brando.SSG.SSH
  alias Brando.SSG.TargetPaths

  @name ".htaccess"
  @redirect_list "_redirects.json"
  # A block is about 90 bytes a redirect
  @limit 262_144
  # What Apache needs to read a file the host has none of
  @default_mode 0o644

  @typedoc """
  What a deploy does with the target's `.htaccess`: write Brando's block,
  remove the block an earlier deploy wrote, or nothing.
  """
  @type mode :: :write | :remove | :none

  @typedoc """
  What the real run sends ahead of the build (`sources`), the rules that go
  before the plan's, and lines for the build log.
  """
  @type step :: %{sources: [String.t()], rules: iodata(), notes: [String.t()]}

  @doc """
  What the deploy of `build` does with the target's `.htaccess`, given
  whether the target's state says a block was written there.
  """
  @spec mode(Build.t(), boolean()) :: mode()
  def mode(%Build{site: site} = build, block_written?) do
    cond do
      option?(site) -> :write
      block_written? and not File.regular?(Path.join(build.build_path, @name)) -> :remove
      true -> :none
    end
  end

  defp option?(%Site{deploy_config: %DeployConfig{htaccess: true}}), do: true
  defp option?(%Site{}), do: false

  @doc "The build's paths the deploy does not send."
  @spec hidden(mode()) :: [TargetPaths.path()]
  def hidden(:write), do: [@redirect_list]
  def hidden(_mode), do: []

  @doc "The build's paths the merged file stands in for: never on the uploaded list."
  @spec replaced(mode()) :: [TargetPaths.path()]
  def replaced(:none), do: []
  def replaced(_mode), do: [@name]

  @doc """
  Fetches and merges the target's `.htaccess` for `mode`, writing the merged
  file in `dir` (the caller's `Brando.SSG.SSH.with_temporary_dir/2`), and
  says what the real run sends. `keep` is the keep list. Takes the deploy's `:runner`.
  """
  @spec prepare(mode(), Build.t(), String.t(), pos_integer(), [TargetPaths.path()], String.t(), keyword()) ::
          {:ok, step()} | {:error, term()}
  def prepare(:none, _build, _target, _port, _keep, _dir, _opts), do: {:ok, %{sources: [], rules: [], notes: []}}

  def prepare(mode, %Build{site: site} = build, target, port, keep, dir, opts) do
    {block, notes} = if mode == :write, do: block(build), else: {nil, []}

    with {:ok, current, file_mode} <- fetch(site, target, port, opts),
         {:ok, step} <- merged(current, Htaccess.merge(current, block), file_mode, keep, dir) do
      {:ok, %{step | notes: own_file_note(mode, build, step.sources) ++ notes}}
    end
  end

  defp merged(_current, {:error, :unterminated_block}, _mode, _keep, _dir), do: {:error, :htaccess_unterminated_block}

  # No file, and none to write
  defp merged(nil, :empty, _mode, _keep, _dir), do: {:ok, %{sources: [], rules: [], notes: []}}

  defp merged(_current, :empty, mode, keep, dir) do
    if TargetPaths.kept?(@name, keep),
      do: send_file("", mode, dir),
      else: {:ok, %{sources: [], rules: TargetPaths.path_rule(:delete, @name), notes: []}}
  end

  # The target's file is the merge already: a build's own is not sent either
  defp merged(current, {:ok, current}, _mode, _keep, _dir),
    do:
      {:ok,
       %{
         sources: [],
         rules: [TargetPaths.path_rule(:hide, @name), TargetPaths.path_rule(:protect, @name)],
         notes: []
       }}

  # Every later fetch would refuse it, the one that removes the block too
  defp merged(_current, {:ok, text}, _mode, _keep, _dir) when byte_size(text) > @limit,
    do: {:error, {:htaccess_merged_too_large, byte_size(text)}}

  defp merged(_current, {:ok, text}, mode, _keep, dir), do: send_file(text, mode, dir)

  defp send_file(text, mode, dir) do
    path = Path.join(dir, @name)

    with :ok <- File.write(path, text),
         :ok <- File.chmod(path, mode) do
      {:ok, %{sources: [path], rules: TargetPaths.path_rule(:protect, @name), notes: []}}
    end
  end

  # No source: the target's file is the merge already, and nothing is sent
  defp own_file_note(:write, build, sources) do
    cond do
      not File.regular?(Path.join(build.build_path, @name)) -> []
      sources == [] -> ["The build's own .htaccess was not uploaded: the target's has Brando's block already"]
      true -> ["The build's own .htaccess was not uploaded: the target's, with Brando's block, was"]
    end
  end

  defp own_file_note(_mode, _build, _sources), do: []

  @doc """
  Brando's block for the build, from its `_redirects.json`, `404.html` and
  Vite manifest, and notes on the redirects it leaves out.
  """
  @spec block(Build.t()) :: {String.t(), [String.t()]}
  def block(%Build{build_path: root, site: site}) do
    manifest_files =
      case read_json(root, "manifest.json") do
        %{} = manifest -> manifest |> Brando.Assets.SiteAssets.manifest_files() |> Enum.filter(&file?(root, &1))
        _none -> []
      end

    languages = {Brando.Languages.codes(site), to_string(Brando.Languages.default_language(site))}

    Htaccess.block(read_json(root, @redirect_list), languages, file?(root, "404.html"), manifest_files)
  end

  defp file?(root, relative), do: match?({:ok, %File.Stat{type: :regular}}, File.lstat(Path.join(root, relative)))

  defp read_json(root, name) do
    with true <- file?(root, name),
         {:ok, json} <- File.read(Path.join(root, name)),
         {:ok, decoded} <- Jason.decode(json) do
      decoded
    else
      _missing_or_invalid -> nil
    end
  end

  @doc """
  The target's `.htaccess`: `{:ok, contents, mode}`, `{:ok, nil, mode}` when
  there is none, or why it could not be read: the transfer's failure,
  `:htaccess_too_large`, `:htaccess_not_a_file` (a link or a directory).
  Takes the deploy's `:runner`.
  """
  @spec fetch(Site.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, binary() | nil, non_neg_integer()} | {:error, term()}
  def fetch(%Site{} = site, target, port, opts) do
    SSH.with_temporary_dir("brando-ssg-htaccess", fn dir ->
      # The target's root with its `.htaccess` alone: no such file is no
      # error. A link stays a link, and is refused below.
      args = [
        "-rlp",
        "--max-size=#{@limit}",
        "--info=skip1",
        "--timeout=30",
        "--filter=+ /#{@name}",
        "--filter=- *",
        "--",
        String.trim_trailing(target, "/") <> "/",
        dir <> "/"
      ]

      case SSH.rsync(site, target, port, args, opts) do
        {:ok, output} -> read_fetched(Path.join(dir, @name), output)
        {:error, {:rsync_failed, _status, _output} = reason} -> {:error, {:htaccess_not_fetched, reason}}
        {:error, _reason} = error -> error
      end
    end)
  end

  defp read_fetched(path, output) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} ->
        with {:ok, text} <- File.read(path), do: {:ok, text, Bitwise.band(mode, 0o7777)}

      {:ok, %File.Stat{}} ->
        {:error, :htaccess_not_a_file}

      # The receiving rsync, here, says when it skips a larger file
      {:error, :enoent} ->
        if String.contains?(output, "#{@name} is over max-size"),
          do: {:error, :htaccess_too_large},
          else: {:ok, nil, @default_mode}

      {:error, reason} ->
        {:error, {:htaccess_not_fetched, reason}}
    end
  end

  @doc """
  Why a deploy stopped at this step, to write in the build log; nil for
  other reasons. A refusal is not retried.
  """
  @spec refusal_message(term()) :: String.t() | nil
  def refusal_message(:htaccess_too_large),
    do:
      "the target's .htaccess is larger than #{div(@limit, 1024)} KB, too large to merge Brando's block into, so nothing was copied."

  def refusal_message({:htaccess_merged_too_large, size}),
    do:
      "the target's .htaccess with Brando's block would be #{size} bytes, more than the #{@limit} bytes Brando can merge its block into, so nothing was copied. The block grows with the site's redirects: shorten the redirects or the host's own lines, or turn the Apache option off."

  def refusal_message(:htaccess_not_a_file),
    do:
      "the target's .htaccess is a link or a directory, not a file Brando can merge its block into, so nothing was copied."

  def refusal_message(:htaccess_unterminated_block),
    do:
      "the target's .htaccess has a # BEGIN Brando line with no # END Brando line after it, so nothing was copied. Remove Brando's block, or add its END line, on the host."

  def refusal_message({:htaccess_not_fetched, {:rsync_failed, status, output}}),
    do:
      "the target's .htaccess could not be fetched (rsync exited with status #{status}: #{SSH.remote_output(output)}), so nothing was copied."

  def refusal_message({:htaccess_not_fetched, reason}),
    do: "the target's .htaccess could not be read (#{inspect(reason)}), so nothing was copied."

  def refusal_message(_reason), do: nil
end
