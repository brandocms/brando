defmodule Brando.Doctor.Checks.Versions do
  @moduledoc """
  Elixir, OTP, Phoenix and LiveView against the ranges this Brando supports:
  the Elixir requirement and the Phoenix and LiveView versions in Brando's
  `mix.exs`, and the oldest OTP release Brando is tested on.

  The summary starts with Brando's version and where it came from
  (`Brando.Doctor.Source`), so it shows whether a fix is live. From the
  terminal, a git source tracking a branch is compared with the branch's
  latest commit on the remote; a difference is noted, but is not a warning.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor.Source

  @project Mix.Project.config()
  @deps Map.new(for dep <- @project[:deps], is_binary(elem(dep, 1)), do: {elem(dep, 0), elem(dep, 1)})

  # The oldest release in the CI matrix
  @otp_minimum 27

  @doc false
  def requirements do
    %{
      elixir: @project[:elixir],
      otp: @otp_minimum,
      phoenix: @deps[:phoenix],
      live_view: @deps[:phoenix_live_view]
    }
  end

  @impl true
  def id, do: "versions"

  @impl true
  def label, do: dgettext("doctor", "Versions")

  @impl true
  def run(context) do
    versions = Brando.Doctor.versions()

    latest =
      if context.mode == :mix and not context.offline?,
        do: Source.latest_commit(versions[:brando_source])

    evaluate(versions, requirements(), latest)
  end

  @doc """
  Compares `versions` (`Brando.Doctor.versions/0`) with `requirements`
  (`requirements/0`). `latest` is the commit Brando's git branch is at on the
  remote (`Brando.Doctor.Source.latest_commit/2`), or `nil` when unknown.
  """
  def evaluate(versions, requirements, latest \\ nil) do
    source = versions[:brando_source]
    moved = moved(source, latest)

    rows = [
      {"Elixir", versions.elixir, requirements.elixir, matches?(versions.elixir, requirements.elixir)},
      {"OTP", versions.otp, ">= #{requirements.otp}", otp_supported?(versions.otp, requirements.otp)},
      {"Phoenix", versions.phoenix, requirements.phoenix, matches?(versions.phoenix, requirements.phoenix)},
      {"LiveView", versions.live_view, requirements.live_view, matches?(versions.live_view, requirements.live_view)}
    ]

    items =
      brando_items(versions.brando, source, moved) ++
        Enum.map(rows, fn {name, version, requirement, _} ->
          dgettext("doctor", "%{name} %{version} (supported: %{requirement})",
            name: name,
            version: version || "-",
            requirement: requirement || "-"
          )
        end)

    case Enum.reject(rows, &elem(&1, 3)) do
      [] ->
        ok("#{brando(versions.brando, source, moved)} · Elixir #{versions.elixir} · OTP #{versions.otp}", items: items)

      unsupported ->
        summary =
          Enum.map_join(unsupported, ", ", fn {name, version, requirement, _} ->
            dgettext("doctor", "%{name} %{version}, needs %{requirement}",
              name: name,
              version: version || "-",
              requirement: requirement
            )
          end)

        error(summary,
          fix: dgettext("doctor", "use the versions this Brando supports (see the installation guide)"),
          items: items
        )
    end
  end

  # "Brando 0.55.0 (git 12c2289, branch main; main is now at a1b2c3d)"
  defp brando(version, source, moved) do
    notes =
      Enum.reject(
        [
          Source.describe(source),
          moved &&
            dgettext("doctor", "%{branch} is now at %{commit}", branch: branch(source), commit: Source.short(moved))
        ],
        &is_nil/1
      )

    case notes do
      [] -> "Brando #{version}"
      notes -> "Brando #{version} (#{Enum.join(notes, "; ")})"
    end
  end

  defp brando_items(version, source, moved) do
    Enum.reject(
      [
        brando(version, source, nil),
        match?(%{type: :git}, source) &&
          dgettext("doctor", "commit %{commit} from %{url}", commit: source.commit, url: source.url),
        moved &&
          dgettext("doctor", "the locked commit is not the latest on %{branch} (%{commit}): mix deps.update brando",
            branch: branch(source),
            commit: Source.short(moved)
          )
      ],
      &(&1 in [nil, false])
    )
  end

  # The remote's commit, when it differs from the one Brando was built from
  defp moved(%{type: :git, commit: commit}, latest) when is_binary(latest) and latest != commit, do: latest
  defp moved(_source, _latest), do: nil

  defp branch(%{branch: branch}) when is_binary(branch), do: branch
  defp branch(_source), do: dgettext("doctor", "the default branch")

  defp matches?(nil, _requirement), do: false
  defp matches?(_version, nil), do: true

  defp matches?(version, requirement) do
    Version.match?(version, requirement, allow_pre: true)
  rescue
    Version.InvalidVersionError -> false
    Version.InvalidRequirementError -> true
  end

  defp otp_supported?(release, minimum) do
    case Integer.parse(to_string(release)) do
      {major, _} -> major >= minimum
      :error -> false
    end
  end
end
