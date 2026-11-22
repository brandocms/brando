defmodule Brando.Sites.Usage.Measure do
  @moduledoc """
  Measures what one site stores (`Brando.Sites.Usage`):

    * its media folder (`Brando.Tenant.Storage.media_root/1`);
    * its kept static builds (`Brando.SSG.Builds.build_root/1`), whatever its
      delivery mode is today;
    * each of its database schemas: every environment's, and every archive of
      one, listed under the environment its name carries.

  Folders are walked without following a link inside them; the root itself
  may be one, as a release's media folder is. A folder it cannot read fails
  the measurement. A schema that disappears between listing and sizing is
  left out.
  """

  alias Brando.Sites.Site
  alias Brando.SSG.Builds
  alias Brando.Tenant.Storage

  @doc "The site's sizes, as `Brando.Sites.Usage.put_measurement/3` takes them."
  @spec site(Site.t()) :: %{media_bytes: non_neg_integer(), builds_bytes: non_neg_integer(), databases: [map()]}
  def site(%Site{} = site) do
    %{
      media_bytes: directory_bytes(Storage.media_root(site)),
      builds_bytes: directory_bytes(Builds.build_root(site)),
      databases: databases(site)
    }
  end

  @doc """
  The free bytes on the volume holding `path`, as `df` reports them to an
  unprivileged user; nil when it cannot tell.

  `df` runs in a process of its own: the port it runs in is linked to the
  process that opens it, and a caller that traps exits, as a LiveView does,
  would get that port's exit as a message.
  """
  @spec free_bytes(String.t()) :: non_neg_integer() | nil
  def free_bytes(path) do
    {pid, ref} = spawn_monitor(fn -> exit({:free_bytes, df_available(path)}) end)

    receive do
      {:DOWN, ^ref, :process, ^pid, {:free_bytes, bytes}} -> bytes
      {:DOWN, ^ref, :process, ^pid, _reason} -> nil
    after
      5_000 ->
        Process.demonitor(ref, [:flush])
        Process.exit(pid, :kill)
        nil
    end
  end

  defp df_available(path) do
    with {output, 0} <- System.cmd("df", ["-Pk", path], stderr_to_stdout: true),
         [_header, line | _] <- String.split(output, "\n", trim: true),
         [_filesystem, _blocks, _used, available | _] <- String.split(line),
         {kilobytes, ""} <- Integer.parse(available) do
      kilobytes * 1024
    else
      _ -> nil
    end
  rescue
    ErlangError -> nil
  end

  @doc """
  The bytes of the regular files under `path`, without following links
  inside it. 0 for a path that does not exist; raises `File.Error` for a
  folder it cannot read, so a measurement is never short of it.
  """
  @spec directory_bytes(String.t()) :: non_neg_integer()
  def directory_bytes(path) do
    case File.ls(path) do
      {:ok, entries} -> Enum.reduce(entries, 0, &(&2 + entry_bytes(Path.join(path, &1))))
      {:error, :enoent} -> 0
      {:error, reason} -> raise File.Error, reason: reason, action: "list directory", path: path
    end
  end

  defp entry_bytes(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} -> size
      {:ok, %File.Stat{type: :directory}} -> directory_bytes(path)
      _link_other_or_gone -> 0
    end
  end

  # The site's schemas are named `tenant_<site>_<environment>`, and an
  # archive of one `…_archive_<timestamp>` (`Brando.Environments`). Keys
  # hold no underscore, so the environment is the part before `_archive_`.
  defp databases(%Site{key: key}) do
    pattern = "tenant_#{key}\\_%"

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Brando.Repo.repo(),
        "SELECT nspname FROM pg_namespace WHERE nspname LIKE $1 ESCAPE '\\' ORDER BY nspname",
        [pattern]
      )

    for [schema] <- rows, bytes = schema_bytes(schema), is_integer(bytes) do
      [base | archive] = String.split(schema, "_archive_", parts: 2)
      %{"schema" => schema, "environment" => environment_key(base, key), "archive" => archive != [], "bytes" => bytes}
    end
  end

  # An archive of a long name is cut short (`Brando.Environments`), and may
  # carry no whole environment key
  defp environment_key(base, site_key) do
    case String.split(base, "tenant_#{site_key}_", parts: 2) do
      ["", environment] -> environment
      _cut -> nil
    end
  end

  @doc """
  A schema's tables with their indexes and TOAST, in bytes; nil for a schema
  that does not exist, or was dropped while it was sized.
  """
  @spec schema_bytes(String.t()) :: non_neg_integer() | nil
  def schema_bytes(schema) do
    sql = """
    SELECT to_regnamespace($1) IS NOT NULL,
           (SELECT coalesce(sum(pg_total_relation_size(c.oid)), 0)::bigint
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = $1 AND c.relkind IN ('r', 'm'))
    """

    case Ecto.Adapters.SQL.query(Brando.Repo.repo(), sql, [schema]) do
      {:ok, %{rows: [[true, bytes]]}} -> bytes
      _gone -> nil
    end
  end
end
