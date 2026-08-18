defmodule Brando.Environments.SchemaCloner.Postgres do
  @moduledoc """
  PostgreSQL schema cloning through `pg_dump` and `psql`.

  Dumps use plain SQL with every identifier quoted. The source schema's exact
  quoted identifier is then rewritten before restoring with `ON_ERROR_STOP`, so
  tables, data, sequences, constraints, functions, and migration history move
  together. Database passwords are passed through `PGPASSWORD`, never process
  arguments.
  """

  @behaviour Brando.Environments.SchemaCloner

  require Logger

  @safe_identifier ~r/^[a-z0-9_-]+$/

  @impl true
  def clone_schema(source_prefix, target_prefix) do
    with :ok <- validate_identifier(source_prefix),
         :ok <- validate_identifier(target_prefix),
         {:ok, dump} <- dump_schema(source_prefix),
         {:ok, rewritten_dump} <- rewrite_schema(dump, source_prefix, target_prefix) do
      restore_dump(rewritten_dump)
    end
  end

  @doc "Rewrites quoted schema identifiers in a plain PostgreSQL dump."
  def rewrite_schema(dump, source_prefix, target_prefix) do
    source_identifier = ~s|"#{source_prefix}"|

    if String.contains?(dump, source_identifier) do
      target_identifier = ~s|"#{target_prefix}"|
      {:ok, rewrite_dump(dump, source_identifier, target_identifier)}
    else
      {:error, {:source_schema_not_found_in_dump, source_prefix}}
    end
  end

  defp rewrite_dump(dump, source_identifier, target_identifier) do
    dump
    |> String.split("\n")
    |> Enum.map_reduce(:sql, &rewrite_dump_line(&1, &2, source_identifier, target_identifier))
    |> elem(0)
    |> Enum.join("\n")
  end

  defp rewrite_dump_line("\\." = line, :copy_data, _source, _target), do: {line, :sql}
  defp rewrite_dump_line(line, :copy_data, _source, _target), do: {line, :copy_data}

  defp rewrite_dump_line(line, :sql, source_identifier, target_identifier) do
    rewritten_line = String.replace(line, source_identifier, target_identifier)
    next_state = if copy_from_stdin?(line), do: :copy_data, else: :sql
    {rewritten_line, next_state}
  end

  defp copy_from_stdin?(line) do
    String.starts_with?(line, "COPY ") and String.ends_with?(line, " FROM stdin;")
  end

  @doc """
  Dumps one PostgreSQL schema as quoted, restorable plain SQL.

  The dump is written with `--file` rather than read from standard output.
  pg_dump reports warnings — circular foreign keys, unsupported objects — on
  standard error, and capturing both streams together would splice that prose
  into the SQL, where psql then fails on it.
  """
  def dump_schema(prefix, extra_args \\ []) do
    with :ok <- validate_identifier(prefix),
         {:ok, executable} <- executable(:pg_dump_path, "pg_dump"),
         {:ok, path} <- temporary_path() do
      try do
        executable
        |> System.cmd(dump_args(prefix, path, extra_args),
          env: connection_env(),
          stderr_to_stdout: true
        )
        |> read_dump(path)
      after
        File.rm(path)
      end
    end
  end

  defp dump_args(prefix, path, extra_args) do
    connection_args() ++
      [
        "--schema",
        prefix,
        "--format",
        "plain",
        "--no-owner",
        "--no-privileges",
        "--quote-all-identifiers",
        "--file",
        path
      ] ++ extra_args
  end

  defp read_dump({diagnostics, 0}, path) do
    log_diagnostics(diagnostics)

    case File.read(path) do
      {:ok, sql} -> {:ok, sql}
      {:error, reason} -> {:error, {:dump_unreadable, reason}}
    end
  end

  defp read_dump({output, status}, _path),
    do: {:error, {:pg_dump_failed, status, String.trim(output)}}

  defp log_diagnostics(diagnostics) do
    case String.trim(diagnostics) do
      "" -> :ok
      message -> Logger.warning("pg_dump reported:\n#{message}")
    end
  end

  @doc "Restores a plain SQL dump with PostgreSQL's stop-on-error mode enabled."
  def restore_dump(sql) do
    with {:ok, executable} <- executable(:psql_path, "psql"),
         {:ok, path} <- write_temporary_dump(sql) do
      try do
        case System.cmd(
               executable,
               connection_args() ++ ["--set", "ON_ERROR_STOP=1", "--file", path],
               env: connection_env(),
               stderr_to_stdout: true
             ) do
          {_output, 0} -> :ok
          {output, status} -> {:error, {:psql_failed, status, String.trim(output)}}
        end
      after
        File.rm(path)
      end
    end
  end

  defp write_temporary_dump(sql) do
    case temporary_path() do
      {:ok, path} ->
        case File.write(path, sql) do
          :ok ->
            {:ok, path}

          {:error, reason} ->
            File.rm(path)
            {:error, {:temporary_dump_failed, reason}}
        end

      {:error, _reason} = error ->
        error
    end
  end

  # Created empty and locked down before pg_dump writes into it, so the dump is
  # never briefly world-readable.
  defp temporary_path do
    path =
      Path.join(
        System.tmp_dir!(),
        "brando-tenant-#{System.unique_integer([:positive, :monotonic])}.sql"
      )

    case File.write(path, "", [:exclusive]) do
      :ok ->
        File.chmod!(path, 0o600)
        {:ok, path}

      {:error, reason} ->
        {:error, {:temporary_dump_failed, reason}}
    end
  end

  defp executable(config_key, default) do
    configured = Brando.config(config_key)

    case configured || System.find_executable(default) || sibling_of_pg_dump(default) do
      nil -> {:error, {:executable_not_found, default}}
      executable -> {:ok, executable}
    end
  end

  defp sibling_of_pg_dump("psql") do
    with pg_dump when is_binary(pg_dump) <-
           Brando.config(:pg_dump_path) || System.find_executable("pg_dump"),
         candidate = pg_dump |> resolve_link() |> Path.dirname() |> Path.join("psql"),
         true <- File.regular?(candidate) do
      candidate
    else
      _ -> nil
    end
  end

  defp sibling_of_pg_dump(_executable), do: nil

  defp resolve_link(path) do
    case File.read_link(path) do
      {:ok, target} ->
        if Path.type(target) == :absolute,
          do: target,
          else: Path.expand(target, Path.dirname(path))

      {:error, _reason} ->
        path
    end
  end

  defp connection_args do
    config = Brando.Repo.repo().config()

    [
      {"--host", config[:hostname]},
      {"--port", config[:port] || 5432},
      {"--username", config[:username]},
      {"--dbname", config[:database]}
    ]
    |> Enum.reject(fn {_flag, value} -> is_nil(value) end)
    |> Enum.flat_map(fn {flag, value} -> [flag, to_string(value)] end)
  end

  defp connection_env do
    config = Brando.Repo.repo().config()

    []
    |> maybe_put_env("PGPASSWORD", config[:password])
    |> maybe_put_env("PGSSLMODE", config[:ssl] && "require")
  end

  defp maybe_put_env(env, _key, nil), do: env
  defp maybe_put_env(env, _key, false), do: env
  defp maybe_put_env(env, key, value), do: [{key, to_string(value)} | env]

  defp validate_identifier(identifier) do
    if is_binary(identifier) and Regex.match?(@safe_identifier, identifier) and
         byte_size(identifier) <= 63 do
      :ok
    else
      {:error, {:invalid_schema_identifier, identifier}}
    end
  end
end
