defmodule Brando.Sites.Usage.Measure do
  @moduledoc """
  Measures what one site stores (`Brando.Sites.Usage`):

    * its media folder (`Brando.Tenant.Storage.media_root/1`);
    * its kept static builds (`Brando.SSG.Builds.build_root/1`), whatever its
      delivery mode is today;
    * each of its database schemas: every environment's, and every archive of
      one, listed under the environment its name carries.

  Folders are walked without following a link inside them; the media root
  itself may be one, as a release's media folder is. The builds are reached
  from the site's folder (`Brando.Tenant.Storage.site_root/1`) only through
  folders that are no links. A folder it cannot read fails the measurement,
  and so does a sizing query that fails; a schema that disappears between
  listing and sizing is left out.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments
  alias Brando.Environments.OperationLog
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Storage

  @doc "The site's sizes, as `Brando.Sites.Usage.put_measurement/3` takes them."
  @spec site(Site.t()) :: %{media_bytes: non_neg_integer(), builds_bytes: non_neg_integer(), databases: [map()]}
  def site(%Site{} = site) do
    %{
      media_bytes: directory_bytes(Storage.media_root(site)),
      builds_bytes: builds_bytes(site),
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

  # `<site>/ssg/builds`, never through a link: one could lead into another
  # site's folder
  defp builds_bytes(site), do: bytes_below(Storage.site_root(site), ["ssg", "builds"])

  defp bytes_below(path, []), do: directory_bytes(path)

  defp bytes_below(path, [name | rest]) do
    path = Path.join(path, name)

    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> bytes_below(path, rest)
      {:ok, _link_or_file} -> 0
      {:error, :enoent} -> 0
      {:error, reason} -> raise File.Error, reason: reason, action: "read file stats", path: path
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
  # archive of one `…_archive_<timestamp>` (`Brando.Environments`); keys hold
  # no underscore. An archive whose name would be too long is cut to its
  # first 31 bytes and a hash of the whole name: the site's environments
  # give the names their archives are cut to, and the operation log the cut
  # archives of environments since deleted, listed under no environment.
  @own ~r/^([a-z0-9-]+)(_archive_\d{14})?$/
  @cut ~r/^(.{31})_archive_\d{14}_([a-f0-9]{8})$/

  defp databases(%Site{} = site) do
    prefix = "tenant_#{site.key}_"
    cut = cut_names(site)
    logged = logged_archives(site)

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Brando.Repo.repo(),
        "SELECT nspname FROM pg_namespace WHERE nspname LIKE 'tenant\\_%' ESCAPE '\\' ORDER BY nspname",
        []
      )

    for [schema] <- rows,
        {environment, archive?} <- [own(schema, prefix) || cut_archive(schema, cut, logged)],
        bytes = schema_bytes(schema),
        is_integer(bytes) do
      %{"schema" => schema, "environment" => environment, "archive" => archive?, "bytes" => bytes}
    end
  end

  defp own(schema, prefix) do
    with true <- String.starts_with?(schema, prefix),
         rest = binary_part(schema, byte_size(prefix), byte_size(schema) - byte_size(prefix)),
         [_rest, environment | archive] <- Regex.run(@own, rest) do
      {environment, archive != []}
    else
      _ -> nil
    end
  end

  defp cut_archive(schema, cut, logged) do
    case Regex.run(@cut, schema, capture: :all_but_first) do
      [base, hash] ->
        case Map.fetch(cut, {base, hash}) do
          {:ok, environment} -> {environment, true}
          :error -> if MapSet.member?(logged, schema), do: {nil, true}
        end

      nil ->
        nil
    end
  end

  defp cut_names(site) do
    for environment <- Registry.list_environments(site),
        name = Environments.archive_prefix(Tenant.prefix(site, environment), "00000000000000"),
        [base, hash] <- [Regex.run(@cut, name, capture: :all_but_first)],
        into: %{},
        do: {{base, hash}, environment.key}
  end

  defp logged_archives(%Site{id: site_id}) do
    from(log in OperationLog,
      where: log.site_id == ^site_id and not is_nil(log.archive_schema),
      select: log.archive_schema
    )
    |> Brando.Repo.all(prefix: "public")
    |> MapSet.new()
  end

  @doc """
  A schema's tables with their indexes and TOAST, in bytes; nil for a schema
  that does not exist, or was dropped while it was sized. Raises when the
  query fails.
  """
  @spec schema_bytes(String.t()) :: non_neg_integer() | nil
  def schema_bytes(schema) do
    sql = """
    SELECT to_regnamespace($1) IS NOT NULL,
           (SELECT coalesce(sum(pg_total_relation_size(c.oid)), 0)::bigint
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = $1 AND c.relkind IN ('r', 'm'))
    """

    case Ecto.Adapters.SQL.query!(Brando.Repo.repo(), sql, [schema]) do
      %{rows: [[true, bytes]]} -> bytes
      %{rows: [[false, _bytes]]} -> nil
    end
  end
end
