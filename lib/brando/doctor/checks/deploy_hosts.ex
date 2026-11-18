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
  match: a site whose domain really is `<app>.com` can skip the check. A file
  with no `PHX_HOST`, or an empty one, is a warning too: a Phoenix
  `config/runtime.exs` then falls back to its own default host.
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

    placeholders = for {file, host, expected} <- found, host == expected, do: {file, host}
    # Without one, a Phoenix runtime.exs falls back to its own default host
    missing = for {file, host, _expected} <- found, host in [nil, ""], do: file

    cond do
      found == [] ->
        skipped(dgettext("doctor", "no .envrc.prod or .envrc.staging"))

      placeholders == [] and missing == [] ->
        ok(dgettext("doctor", "PHX_HOST set in %{files}", files: files(found)))

      true ->
        summary =
          if placeholders == [],
            do: dgettext("doctor", "no PHX_HOST: %{files}", files: files(missing)),
            else: dgettext("doctor", "PHX_HOST still the installer's placeholder: %{files}", files: files(placeholders))

        items =
          Enum.map(placeholders, fn {file, host} -> "#{file}: PHX_HOST=#{host}" end) ++
            Enum.map(missing, &dgettext("doctor", "%{file}: no PHX_HOST", file: &1))

        warning(summary, fix: fix(), items: items)
    end
  end

  defp files(found), do: Enum.map_join(found, ", ", fn file -> if is_tuple(file), do: elem(file, 0), else: file end)

  defp fix do
    dgettext(
      "doctor",
      "set PHX_HOST in them to the host each release serves before deploying; the installer writes it from --domain only when the files are new"
    )
  end

  # The last assignment wins when the file is sourced
  defp phx_host(contents) do
    case Regex.scan(~r/^[ \t]*(?:export[ \t]+)?PHX_HOST=["']?([^"'\s#]*)/m, contents) do
      [] -> nil
      matches -> matches |> List.last() |> List.last() |> String.downcase()
    end
  end
end
