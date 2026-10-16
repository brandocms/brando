defmodule Mix.Tasks.Brando.Install.Secrets do
  use Mix.Task
  @moduledoc false

  # brando.install plans the environment files with markers, so its diff and
  # --dry-run output never show a secret, and queues this task to fill them in
  # once the plan is accepted. Only the installer's own files are accepted.
  @files ~w(.envrc.prod .envrc.staging)
  @markers %{
    "__BRANDO_SECRET_KEY_BASE__" => :secret_key_base,
    "__BRANDO_DATABASE_PASSWORD__" => :database_password
  }

  @impl Mix.Task
  def run([_ | _] = paths) do
    case Enum.reject(paths, &(&1 in @files)) do
      [] -> Enum.each(paths, &fill!/1)
      unknown -> Mix.raise("Unknown environment file: #{Enum.join(unknown, ", ")}")
    end
  end

  def run(_argv), do: Mix.raise("This internal task requires the environment files to fill in.")

  defp fill!(path) do
    contents =
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, reason} -> Mix.raise("Cannot read #{path}: #{:file.format_error(reason)}")
      end

    filled = Enum.reduce(@markers, contents, fn {marker, kind}, acc -> String.replace(acc, marker, secret(kind)) end)

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

  defp secret(:secret_key_base), do: :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64)
  defp secret(:database_password), do: :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
end
