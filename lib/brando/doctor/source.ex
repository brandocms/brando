defmodule Brando.Doctor.Source do
  @moduledoc """
  Where the running Brando came from: a git commit, a Hex release, a local
  path, or this checkout when Brando is the project itself.

  It is recorded when Brando is compiled, from what Mix gives a dependency:
  its SCM and its entry in the application's `mix.lock`. Mix compiles a git
  or Hex dependency from scratch when its lock entry changes, so the source
  always belongs to the code that runs, also in a release, where there is no
  `mix.lock` to read. Reading the lock at runtime would instead report a
  `mix deps.update` that the running server has not been rebuilt with.

  A path dependency has no lock entry; its path is shown relative to the
  application.
  """
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Source.Lock

  @type t ::
          %{
            type: :git,
            url: String.t(),
            commit: String.t(),
            branch: String.t() | nil,
            tag: String.t() | nil,
            ref: String.t() | nil
          }
          | %{type: :hex, version: String.t()}
          | %{type: :path, path: String.t()}
          | %{type: :checkout}
          | %{type: :unknown}

  # Brando's root, where this file's mix.exs is
  @dir Path.expand("../../..", __DIR__)

  # Compiled as a dependency, Mix gives Brando the application's lockfile and
  # its SCM (`Mix.Dep.in_dependency/3`), and in recent Elixir versions its lock
  # entry as `:deps_lock`; otherwise the entry is read from the lockfile.
  @build (if Code.ensure_loaded?(Mix.Project) and Mix.Project.get() do
            config = Mix.Project.config()
            lockfile = Path.expand(config[:lockfile] || "mix.lock")

            lock =
              config[:deps_lock] ||
                case File.read(lockfile) do
                  {:ok, contents} -> Lock.entry(contents, :brando)
                  {:error, _} -> nil
                end

            %{scm: config[:build_scm], lockfile: lockfile, lock: lock}
          else
            :unknown
          end)

  @remote_timeout 3_000

  @doc "Where the running Brando was compiled from."
  @spec current() :: t()
  def current, do: from_build(@build, @dir)

  @doc """
  The source for how Mix compiled Brando in `dir`: `:scm`, the dependency's
  SCM module, `:lockfile`, the expanded path of the project's `mix.lock`,
  and `:lock`, Brando's entry in it. Brando is the project itself when the
  lockfile is its own.
  """
  @spec from_build(map() | :unknown, Path.t()) :: t()
  def from_build(:unknown, _dir), do: %{type: :unknown}

  def from_build(%{lockfile: lockfile} = build, dir) do
    cond do
      Path.dirname(lockfile) == dir -> %{type: :checkout}
      is_tuple(build[:lock]) -> from_lock(build.lock)
      build[:scm] == Mix.SCM.Path -> %{type: :path, path: Path.relative_to(dir, Path.dirname(lockfile), force: true)}
      true -> %{type: :unknown}
    end
  end

  @doc """
  The source for a dependency's entry in `mix.lock`:

      iex> Brando.Doctor.Source.from_lock({:git, "https://github.com/brandocms/brando.git", "12c2289e98fa", [branch: "main"]})
      %{
        type: :git,
        url: "https://github.com/brandocms/brando.git",
        commit: "12c2289e98fa",
        branch: "main",
        tag: nil,
        ref: nil
      }

      iex> Brando.Doctor.Source.from_lock({:hex, :brando, "0.55.0", "abc", [:mix], [], "hexpm", "def"})
      %{type: :hex, version: "0.55.0"}
  """
  @spec from_lock(tuple()) :: t()
  def from_lock({:git, url, commit, opts}) when is_binary(url) and is_binary(commit) and is_list(opts) do
    %{
      type: :git,
      url: url,
      commit: commit,
      branch: option(opts, :branch),
      tag: option(opts, :tag),
      ref: option(opts, :ref)
    }
  end

  def from_lock(lock)
      when is_tuple(lock) and tuple_size(lock) >= 3 and elem(lock, 0) == :hex and is_binary(elem(lock, 2)),
      do: %{type: :hex, version: elem(lock, 2)}

  def from_lock(_lock), do: %{type: :unknown}

  @doc """
  A short description for the doctor's header and the Versions check:
  "git 12c2289, branch main", "Hex", "path ../brando", "this checkout". `nil`
  when the source is unknown.
  """
  @spec describe(t() | nil) :: String.t() | nil
  def describe(%{type: :git, commit: commit, branch: branch}) when is_binary(branch),
    do: dgettext("doctor", "git %{commit}, branch %{branch}", commit: short(commit), branch: branch)

  def describe(%{type: :git, commit: commit, tag: tag}) when is_binary(tag),
    do: dgettext("doctor", "git %{commit}, tag %{tag}", commit: short(commit), tag: tag)

  def describe(%{type: :git, commit: commit}), do: dgettext("doctor", "git %{commit}", commit: short(commit))
  def describe(%{type: :hex}), do: dgettext("doctor", "Hex")
  def describe(%{type: :path, path: path}), do: dgettext("doctor", "path %{path}", path: path)
  def describe(%{type: :checkout}), do: dgettext("doctor", "this checkout")
  def describe(_source), do: nil

  @doc "A commit's first seven characters."
  @spec short(String.t()) :: String.t()
  def short(commit), do: String.slice(commit, 0, 7)

  @doc """
  The commit that a git source's branch points at on the remote now, with
  `git ls-remote`. The default branch when the lock names no branch; `nil` for
  a tag or a pinned ref, which are not meant to move.

  Returns `nil` on any failure: no git, no network, a private repository
  that would ask for credentials, or no answer within three seconds.

    * `:runner` — runs the command, `System.cmd/3` by default.
    * `:timeout` — milliseconds to wait.
  """
  @spec latest_commit(t() | nil, keyword()) :: String.t() | nil
  def latest_commit(source, opts \\ [])

  def latest_commit(%{type: :git, url: url, tag: nil, ref: nil} = source, opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)
    ref = if source.branch, do: "refs/heads/#{source.branch}", else: "HEAD"
    task = Task.async(fn -> ls_remote(runner, url, ref) end)

    case Task.yield(task, Keyword.get(opts, :timeout, @remote_timeout)) || Task.shutdown(task, :brutal_kill) do
      {:ok, commit} -> commit
      _ -> nil
    end
  end

  def latest_commit(_source, _opts), do: nil

  defp ls_remote(runner, url, ref) do
    case runner.("git", ["ls-remote", "--", url, ref], env: git_env(), stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/^([0-9a-f]{40})\t/m, output) do
          [_, commit] -> commit
          nil -> nil
        end

      _ ->
        nil
    end
  rescue
    # git is not installed
    _ -> nil
  end

  # Never stop to ask for credentials or a host key
  defp git_env do
    ssh = if System.get_env("GIT_SSH_COMMAND"), do: [], else: [{"GIT_SSH_COMMAND", "ssh -o BatchMode=yes"}]
    [{"GIT_TERMINAL_PROMPT", "0"} | ssh]
  end

  defp option(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value -> to_string(value)
    end
  end
end
