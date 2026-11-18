defmodule Brando.Doctor.Checks.DeployHosts do
  @moduledoc """
  Whether `.envrc.prod` and `.envrc.staging`, the release environments
  Florist uploads, still set `PHX_HOST` to the placeholder `mix brando.install`
  writes without `--domain`: `<app>.com` in `.envrc.prod` and
  `staging.<app>.com` in `.envrc.staging`, with the application name's
  underscores as hyphens. The endpoint's URL host is `PHX_HOST`, so a release
  deployed with it builds links, redirects and LiveView's origin check for a
  domain the site does not have.

  Only a file's last uncommented `PHX_HOST` line counts, and only an exact
  match: a site whose domain really is `<app>.com` can skip the check.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Context
  alias Mix.Brando.Install.Hosts

  @files [{".envrc.prod", ""}, {".envrc.staging", "staging."}]

  @impl true
  def id, do: "deploy_hosts"

  @impl true
  def label, do: dgettext("doctor", "Deploy hosts")

  @impl true
  def needs_source?, do: true

  @impl true
  def run(%Context{root: root}), do: evaluate(root, Brando.otp_app())

  @doc "The result for the environment files in `root`, for the OTP application `app`."
  @spec evaluate(Path.t(), atom() | String.t()) :: Brando.Doctor.Result.t()
  def evaluate(root, app) do
    placeholder = Hosts.placeholder(app)

    found =
      for {file, prefix} <- @files,
          {:ok, contents} <- [File.read(Path.join(root, file))],
          do: {file, phx_host(contents), prefix <> placeholder}

    case for({file, host, expected} <- found, host == expected, do: {file, host}) do
      [] when found == [] ->
        skipped(dgettext("doctor", "no .envrc.prod or .envrc.staging"))

      [] ->
        ok(dgettext("doctor", "%{files} set their own PHX_HOST", files: Enum.map_join(found, " and ", &elem(&1, 0))))

      placeholders ->
        warning(
          dgettext("doctor", "%{files} still set PHX_HOST to the installer's placeholder",
            files: Enum.map_join(placeholders, " and ", &elem(&1, 0))
          ),
          fix:
            dgettext(
              "doctor",
              "set PHX_HOST in them to the host each release serves before deploying; the installer writes it from --domain only when the files are new"
            ),
          items: Enum.map(placeholders, fn {file, host} -> "#{file}: PHX_HOST=#{host}" end)
        )
    end
  end

  # The last assignment wins when the file is sourced
  defp phx_host(contents) do
    case Regex.scan(~r/^[ \t]*(?:export[ \t]+)?PHX_HOST=["']?([^"'\s#]*)/m, contents) do
      [] -> nil
      matches -> matches |> List.last() |> List.last() |> String.downcase()
    end
  end
end
