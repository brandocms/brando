defmodule Brando.Doctor.Report do
  @moduledoc """
  Formats `Brando.Doctor` results for the terminal and for scripts.
  """

  alias Brando.Doctor
  alias Brando.Doctor.Result
  alias Brando.Doctor.Source

  @column 29

  @doc """
  The terminal report as ANSI data for `Mix.shell().info/1`: the versions, a
  line per check with its fix under it, and a summary. With `verbose: true`,
  each check's items are listed too.
  """
  @spec text([Result.t()], map(), keyword()) :: IO.ANSI.ansidata()
  def text(results, versions, opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    [
      [:faint, header(versions), :reset, "\n\n"],
      Enum.map(results, &check_lines(&1, verbose?)),
      "\n",
      footer(results, verbose?)
    ]
  end

  @doc """
  The header line: Brando's version and source, Phoenix and LiveView
  versions.
  """
  def header(versions) do
    brando =
      case Source.describe(versions[:brando_source]) do
        nil -> "Brando #{versions.brando}"
        source -> "Brando #{versions.brando} (#{source})"
      end

    [
      brando,
      versions.phoenix && "Phoenix #{versions.phoenix}",
      versions.live_view && "LiveView #{versions.live_view}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp check_lines(%Result{} = result, verbose?) do
    label = String.pad_trailing(result.label || result.id || "", @column - 2)
    indent = String.duplicate(" ", @column)

    fix = if result.fix && result.status != :ok, do: [indent, :faint, result.fix, :reset, "\n"], else: []
    items = if verbose?, do: Enum.map(result.items, &[indent, :faint, "· ", &1, :reset, "\n"]), else: []

    [mark(result.status), " ", label, result.summary, "\n", fix, items]
  end

  defp mark(:ok), do: [:green, "✓", :reset]
  defp mark(:warning), do: [:yellow, "!", :reset]
  defp mark(:error), do: [:red, "✗", :reset]
  defp mark(:skipped), do: [:faint, "–", :reset]

  defp footer(results, verbose?) do
    counts = Doctor.counts(results)

    problems =
      [
        counts.warning > 0 && count(counts.warning, "warning", "warnings"),
        counts.error > 0 && count(counts.error, "error", "errors")
      ]
      |> Enum.filter(& &1)

    skipped = if counts.skipped > 0, do: " #{count(counts.skipped, "check", "checks")} skipped.", else: ""

    case problems do
      [] ->
        [:green, "All checks passed.", :reset, skipped, "\n"]

      problems ->
        details = if verbose?, do: [], else: [:faint, " Details: mix brando.doctor --verbose", :reset]
        [:blue, Enum.join(problems, ", "), ".", :reset, skipped, details, "\n"]
    end
  end

  defp count(1, singular, _plural), do: "1 #{singular}"
  defp count(n, _singular, plural), do: "#{n} #{plural}"

  @doc """
  The report as a map for `--json`:

      %{
        "status" => "warning",
        "versions" => %{
          "brando" => "0.55.0",
          "brando_source" => %{"type" => "git", "commit" => "12c2289…", "branch" => "main", …},
          "elixir" => "1.20.3",
          …
        },
        "counts" => %{"ok" => 8, "warning" => 3, "error" => 0, "skipped" => 1},
        "checks" => [
          %{"id" => "migrations", "label" => "Migrations", "status" => "ok",
            "summary" => "up to date", "fix" => nil, "items" => ["54 run"]}
        ]
      }
  """
  @spec json([Result.t()], map()) :: map()
  def json(results, versions) do
    %{
      "status" => to_string(Doctor.status(results)),
      "versions" => Map.new(versions, fn {key, value} -> {to_string(key), json_value(value)} end),
      "counts" => Map.new(Doctor.counts(results), fn {key, value} -> {to_string(key), value} end),
      "checks" =>
        Enum.map(results, fn result ->
          %{
            "id" => result.id,
            "label" => result.label,
            "status" => to_string(result.status),
            "summary" => result.summary,
            "fix" => result.fix,
            "items" => result.items
          }
        end)
    }
  end

  defp json_value(%{} = map), do: Map.new(map, fn {key, value} -> {to_string(key), json_value(value)} end)
  defp json_value(value) when is_atom(value) and not is_nil(value) and not is_boolean(value), do: to_string(value)
  defp json_value(value), do: value
end
