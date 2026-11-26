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
  # Each file is written to a temporary file beside it, then moved in place.
  # The ignore lines brando.install writes cover the name, so one an
  # interrupted run leaves behind stays out of Git and the Docker build.
  @temporary_suffix ".brando-secrets-"

  @doc "The files this task fills in, in the order it fills them."
  def files, do: @files

  @doc "A new temporary path beside `path`, which the ignore lines cover."
  def temporary_path(path), do: path <> @temporary_suffix <> Integer.to_string(System.unique_integer([:positive]))

  @doc "The `.gitignore` line for the temporary files, at any depth."
  def temporary_ignore, do: "*" <> @temporary_suffix <> "*"

  @doc "Creates an empty file at `path` only its owner can read, for the secrets to be written to."
  def create_private!(path) do
    File.write!(path, "", [:exclusive])
    File.chmod!(path, 0o600)
  end

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
      temporary = temporary_path(path)

      try do
        create_private!(temporary)
        File.write!(temporary, filled, [:binary])
        File.rename!(temporary, path)
      after
        File.rm(temporary)
      end

      Mix.shell().info("Generated the secrets in #{path}")
    end
  end

  # The value one of the files already holds, or a new one. Two different
  # values are the site's choice to make, not this task's, and one it cannot
  # use stops it before it writes anything.
  defp encryption_secret! do
    found =
      for path <- @files,
          {:ok, contents} <- [File.read(path)],
          value <- encryption_values(path, contents),
          value not in ["", @encryption_marker],
          do: {path, usable!(path, value)}

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

  # Only the secret of a `config :brando, Brando.Crypto` call: other settings
  # in the file have secrets of their own.
  defp encryption_values("config/dev.secret.exs" = path, contents) do
    case Code.string_to_quoted(contents) do
      {:ok, quoted} ->
        {_, values} =
          Macro.prewalk(quoted, [], fn
            {:config, _, [:brando, {:__aliases__, _, [:Brando, :Crypto]}, opts]} = node, values when is_list(opts) ->
              {node, values ++ for({:secret, value} <- opts, do: value)}

            node, values ->
              {node, values}
          end)

        values

      {:error, _} ->
        Mix.raise("Cannot read #{path}: it is not valid Elixir. Fix it, then run mix brando.install again.")
    end
  end

  defp encryption_values(_envrc, contents) do
    regex = ~r/^[ \t]*(?:export[ \t]+)?BRANDO_ENCRYPTION_SECRET=["']?([^"'\s]*)/m
    for [_, value] <- Regex.scan(regex, contents), do: value
  end

  defp usable!(path, value) do
    if is_binary(value) and byte_size(value) >= 32 and not String.starts_with?(value, "__BRANDO_") do
      value
    else
      Mix.raise("""
      #{path} holds a Brando.Crypto secret this task cannot use: the site's value is a string of at \
      least 32 bytes. Set it there, then run mix brando.install again.\
      """)
    end
  end

  defp secret(:secret_key_base), do: :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
  defp secret(:database_password), do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
