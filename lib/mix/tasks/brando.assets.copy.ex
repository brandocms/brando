defmodule Mix.Tasks.Brando.Assets.Copy do
  use Mix.Task
  @moduledoc false

  alias Mix.Brando.Install.Templates

  # Rewrite normalizes every file with a trailing newline, including binaries.
  # Igniter schedules this checked copy only after the source diff is accepted.
  # The manifest is the allowlist; argv cannot request an arbitrary source/target.
  @impl Mix.Task
  def run([target, expected_digest]) do
    template = template_target(target)

    case Enum.find(Templates.manifest(), fn
           {:copy, _source, ^template} -> Path.extname(template) == ".ico"
           _ -> false
         end) do
      {:copy, source, ^template} -> copy!(target, Templates.contents(:copy, source), expected_digest)
      _ -> Mix.raise("Unknown Brando binary asset: #{target}")
    end
  end

  def run(_argv), do: Mix.raise("This internal task requires an asset path and its planned SHA-256 digest.")

  # A site's Vite project in assets/sites/<key>/ has assets/frontend's files
  # (Mix.Brando.Igniter.Assets.site_project/3).
  defp template_target("assets/sites/" <> rest = target) do
    with [key, path] <- String.split(rest, "/", parts: 2),
         true <- Brando.Tenant.valid_key?(key) do
      "assets/frontend/" <> path
    else
      _ -> target
    end
  end

  defp template_target(target), do: target

  defp copy!(target, contents, expected_digest) do
    digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)

    if digest != expected_digest,
      do: Mix.raise("#{target}: Brando's asset changed since planning. Rerun the installer to review it.")

    case File.read(target) do
      {:ok, ^contents} -> :ok
      {:ok, _} -> Mix.raise("#{target} changed since planning; refusing to overwrite it.")
      {:error, :enoent} -> create!(target, contents)
      {:error, reason} -> Mix.raise("Cannot read #{target}: #{:file.format_error(reason)}")
    end
  end

  defp create!(target, contents) do
    File.mkdir_p!(Path.dirname(target))
    temporary = target <> ".brando-#{System.unique_integer([:positive])}"

    try do
      File.write!(temporary, contents, [:binary, :exclusive])

      case File.ln(temporary, target) do
        :ok -> Mix.shell().info("Created #{target}")
        {:error, :eexist} -> Mix.raise("#{target} appeared since planning; refusing to overwrite it.")
        {:error, reason} -> Mix.raise("Cannot create #{target}: #{:file.format_error(reason)}")
      end
    after
      File.rm(temporary)
    end
  end
end
