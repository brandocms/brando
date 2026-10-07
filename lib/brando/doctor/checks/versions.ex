defmodule Brando.Doctor.Checks.Versions do
  @moduledoc """
  Elixir, OTP, Phoenix and LiveView against the ranges this Brando supports:
  the Elixir requirement and the Phoenix and LiveView versions in Brando's
  `mix.exs`, and the oldest OTP release Brando is tested on.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

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
  def run(_context), do: evaluate(Brando.Doctor.versions(), requirements())

  @doc """
  Compares `versions` (`Brando.Doctor.versions/0`) with `requirements`
  (`requirements/0`).
  """
  def evaluate(versions, requirements) do
    rows = [
      {"Elixir", versions.elixir, requirements.elixir, matches?(versions.elixir, requirements.elixir)},
      {"OTP", versions.otp, ">= #{requirements.otp}", otp_supported?(versions.otp, requirements.otp)},
      {"Phoenix", versions.phoenix, requirements.phoenix, matches?(versions.phoenix, requirements.phoenix)},
      {"LiveView", versions.live_view, requirements.live_view, matches?(versions.live_view, requirements.live_view)}
    ]

    items =
      ["Brando #{versions.brando}"] ++
        Enum.map(rows, fn {name, version, requirement, _} ->
          dgettext("doctor", "%{name} %{version} (supported: %{requirement})",
            name: name,
            version: version || "-",
            requirement: requirement || "-"
          )
        end)

    case Enum.reject(rows, &elem(&1, 3)) do
      [] ->
        ok("Elixir #{versions.elixir} · OTP #{versions.otp}", items: items)

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
