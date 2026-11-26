defmodule Mix.Tasks.Brando.Install.Secrets do
  use Mix.Task
  @moduledoc false

  # brando.install plans the environment files and config/dev.secret.exs with
  # markers, so its diff and --dry-run output never show a secret, and queues
  # this task to fill them in once the plan is accepted. Only the installer's
  # own files are accepted.
  #
  # Each file gets its own secret_key_base and database password, but
  # Brando.Crypto's secret is the site's one value: when one of the files
  # already holds it (a run that stopped partway, a rerun after a file was
  # removed), the others get that one.
  @files ~w(.envrc.prod .envrc.staging config/dev.secret.exs)
  @markers %{
    "__BRANDO_SECRET_KEY_BASE__" => :secret_key_base,
    "__BRANDO_DATABASE_PASSWORD__" => :database_password
  }
  @encryption_marker "__BRANDO_ENCRYPTION_SECRET__"

  @doc false
  def files, do: @files

  @impl Mix.Task
  def run([_ | _] = paths) do
    case Enum.reject(paths, &(&1 in @files)) do
      [] -> fill_all!(paths)
      unknown -> Mix.raise("Unknown environment file: #{Enum.join(unknown, ", ")}")
    end
  end

  def run(_argv), do: Mix.raise("This internal task requires the environment files to fill in.")

  defp fill_all!(paths) do
    contents = Map.new(paths, &{&1, read!(&1)})

    encryption =
      if Enum.any?(Map.values(contents), &String.contains?(&1, @encryption_marker)), do: encryption_secret!()

    Enum.each(paths, &fill!(&1, contents[&1], encryption))
  end

  defp read!(path) do
    case File.read(path) do
      {:ok, contents} -> contents
      {:error, reason} -> Mix.raise("Cannot read #{path}: #{:file.format_error(reason)}")
    end
  end

  defp fill!(path, contents, encryption) do
    markers = if encryption, do: Map.put(@markers, @encryption_marker, encryption), else: @markers

    filled =
      Enum.reduce(markers, contents, fn
        {marker, kind}, acc when is_atom(kind) -> String.replace(acc, marker, secret(kind))
        {marker, value}, acc -> String.replace(acc, marker, value)
      end)

    if filled != contents do
      temporary = path <> ".brando-#{System.unique_integer([:positive])}"

      try do
        File.write!(temporary, filled, [:binary, :exclusive])
        File.chmod!(temporary, 0o600)
        File.rename!(temporary, path)
      after
        File.rm(temporary)
      end

      Mix.shell().info("Generated the secrets in #{path}")
    end
  end

  # The value one of the files already holds, or a new one. Two different
  # values are the site's choice to make, not this task's.
  defp encryption_secret! do
    found =
      for path <- @files,
          {:ok, contents} <- [File.read(path)],
          value <- encryption_values(path, contents),
          do: {path, value}

    case found |> Enum.map(&elem(&1, 1)) |> Enum.uniq() do
      [] ->
        secret(:secret_key_base)

      [value] ->
        value

      _values ->
        Mix.raise("""
        #{Enum.map_join(found, ", ", &elem(&1, 0))} hold different Brando.Crypto secrets. A site has one, \
        the same in every environment: give them all production's value, then run mix brando.install again.\
        """)
    end
  end

  defp encryption_values("config/dev.secret.exs", contents),
    do: values(~r/\bsecret:\s*"([^"]*)"/, contents)

  defp encryption_values(_envrc, contents),
    do: values(~r/^[ \t]*(?:export[ \t]+)?BRANDO_ENCRYPTION_SECRET=["']?([^"'\s]*)/m, contents)

  defp values(regex, contents) do
    for [_, value] <- Regex.scan(regex, contents), value not in ["", @encryption_marker], do: value
  end

  defp secret(:secret_key_base), do: :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
  defp secret(:database_password), do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
