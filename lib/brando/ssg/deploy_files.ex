defmodule Brando.SSG.DeployFiles do
  @moduledoc """
  A static site's deploy files, in `<site root>/ssg/deploy/`
  (`Brando.Tenant.Storage.site_root/1`), beside its builds and deleted with
  the site: the private key its rsync deploys use (`:key`) and the host keys
  it accepted (`:known_hosts`), both kept by `Brando.SSG.SSH`; the state of
  its reviewed target (`:target_state`) and a deploy's rsync filter rules
  (`:filter`), kept by `Brando.SSG.TargetReview` under the deploy lock.

  The directory is 0700 and each file 0600. A file is written whole, to a
  temporary file in the directory renamed over the old one, so a reader
  finds the old file or the new one and never part of either. A change is
  made holding the lock of the site's deploy files (`with_lock/2`); a
  deploy reads without it.

  Nothing is kept where the installation serves files from: when the
  directory's real path (links followed) is inside the media directory,
  which `Brando.Plug.Media` serves, or the endpoint's static root. Nor in a
  path with characters ssh or rsync read specially (`-e` is split on spaces,
  ssh expands `%` and `~` in file options): only letters, digits and
  `. _ + @ - /`.
  """

  alias Brando.Sites.Site
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Storage
  alias Brando.Utils

  @files %{key: "id_ed25519", known_hosts: "known_hosts", target_state: "target_state", filter: "rsync_filter"}

  @type name :: :key | :known_hosts | :target_state | :filter

  @doc "The site's deploy directory."
  @spec dir(Site.t()) :: String.t()
  def dir(%Site{} = site), do: Path.join([Storage.site_root(site), "ssg", "deploy"])

  @doc "Where the site's file `name` is kept."
  @spec path(Site.t(), name()) :: String.t()
  def path(%Site{} = site, name) when is_map_key(@files, name), do: Path.join(dir(site), Map.fetch!(@files, name))

  @doc """
  Whether the site's deploy directory may hold its files: `:served` inside
  a directory the installation serves, `:unsafe_path` with a character ssh
  or rsync reads specially (see the moduledoc).
  """
  @spec check_location(Site.t()) :: :ok | {:error, :served | :unsafe_path}
  def check_location(%Site{} = site) do
    dir = site |> dir() |> Path.expand()
    real = Utils.real_path(dir)

    cond do
      not Regex.match?(~r/\A[A-Za-z0-9._+@\/-]+\z/, dir) or not Regex.match?(~r/\A[A-Za-z0-9._+@\/-]+\z/, real) ->
        {:error, :unsafe_path}

      Enum.any?(served_roots(), &inside?(real, &1)) ->
        {:error, :served}

      true ->
        :ok
    end
  end

  defp served_roots do
    media = Brando.config(:media_path)
    static = static_root()
    for root <- [media, static], is_binary(root), do: root |> Path.expand() |> Utils.real_path()
  end

  defp static_root do
    with app when is_atom(app) and not is_nil(app) <- Brando.otp_app(),
         priv when is_list(priv) <- :code.priv_dir(app) do
      Path.join(List.to_string(priv), "static")
    else
      _none -> nil
    end
  end

  defp inside?(path, root), do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

  @doc "The site's file `name`: `{:error, :enoent}` when there is none."
  @spec read(Site.t(), name()) :: {:ok, binary()} | {:error, File.posix()}
  def read(%Site{} = site, name), do: File.read(path(site, name))

  @doc "Whether the site has the file `name`."
  @spec exists?(Site.t(), name()) :: boolean()
  def exists?(%Site{} = site, name), do: File.regular?(path(site, name))

  @doc """
  Writes the site's file `name` whole, mode 0600, in a directory that may
  hold it (`check_location/1`). Call it inside `with_lock/2`, or for
  `:target_state` and `:filter` holding the deploy lock.
  """
  @spec write(Site.t(), name(), iodata()) :: :ok | {:error, term()}
  def write(%Site{} = site, name, contents) do
    path = path(site, name)
    temporary = Path.join(dir(site), ".#{Path.basename(path)}.#{System.unique_integer([:positive])}.tmp")

    with :ok <- check_location(site),
         :ok <- make_dir(site),
         :ok <- write_new(temporary, contents),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  # Readable by the owner alone before anything is in it
  defp write_new(path, contents) do
    with {:ok, file} <- :file.open(path, [:write, :exclusive, :binary, :raw]) do
      try do
        with :ok <- File.chmod(path, 0o600), :ok <- :file.write(file, contents), do: :file.sync(file)
      after
        :file.close(file)
      end
    end
  end

  defp make_dir(site) do
    dir = dir(site)
    with :ok <- File.mkdir_p(dir), do: File.chmod(dir, 0o700)
  end

  @doc "Runs `fun` holding the lock a change to the site's files holds."
  @spec with_lock(Site.t(), (-> result)) :: result when result: term()
  def with_lock(%Site{id: id}, fun) when is_integer(id), do: Lock.with(Lock.deploy_files_key(id), fun)
end
