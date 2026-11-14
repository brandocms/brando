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
  line per check with its fix under it, and a summary naming the checks that
  warned or failed. With `verbose: true`, each check's items are listed too.

  With `ascii: true`, the marks, bullets and arrows are ASCII (`+`, `!`, `x`,
  `-`, `->`), for an output that is not Unicode: Erlang prints a character
  above U+00FF there as an escape such as `\\x{2713}`, and the bullet as a byte
  a UTF-8 terminal cannot show.
  """
  @spec text([Result.t()], map(), keyword()) :: IO.ANSI.ansidata()
  def text(results, versions, opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    report = [
      [:faint, header(versions), :reset, "\n\n"],
      Enum.map(results, &check_lines(&1, verbose?)),
      "\n",
      footer(results, verbose?)
    ]

    if Keyword.get(opts, :ascii, false), do: ascii(report), else: report
  end

  @doc """
  Whether standard output takes Unicode. Erlang decides it from the locale
  when the VM starts (`LANG`, `LC_ALL`, `LC_CTYPE`).
  """
  def unicode_output? do
    :io.getopts(:standard_io)[:encoding] == :unicode
  end

  # Characters the report and Brando's checks print, and their ASCII.
  @ascii [
    {"✓", "+"},
    {"✗", "x"},
    {"·", "-"},
    {"→", "->"},
    {"←", "<-"},
    {"…", "..."},
    {"—", "--"},
    {"–", "-"},
    {"‘", "'"},
    {"’", "'"},
    {"“", "\""},
    {"”", "\""}
  ]

  defp ascii(text) when is_binary(text),
    do: Enum.reduce(@ascii, text, fn {from, to}, text -> String.replace(text, from, to) end)

  defp ascii(data) when is_list(data), do: Enum.map(data, &ascii/1)
  defp ascii(data), do: data

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
    # A label as wide as the column still gets a space before the summary
    label = String.pad_trailing(result.label || result.id || "", @column - 3) <> " "
    indent = String.duplicate(" ", @column)

    fix = if result.fix && result.status != :ok, do: [indent, :faint, result.fix, :reset, "\n"], else: []
    items = if verbose?, do: Enum.map(result.items, &[indent, :faint, "· ", &1, :reset, "\n"]), else: []

    [mark(result.status), " ", label, result.summary, "\n", fix, items]
  end

  defp mark(:ok), do: [:green, "✓", :reset]
  defp mark(:warning), do: [:yellow, "!", :reset]
  defp mark(:error), do: [:red, "✗", :reset]
  defp mark(:skipped), do: [:faint, "–", :reset]

  # Names the checks behind each count, errors first: the report above can be
  # long, and in development the application's own log lines may run through it.
  defp footer(results, verbose?) do
    counts = Doctor.counts(results)

    problems =
      for {status, singular, plural} <- [{:error, "error", "errors"}, {:warning, "warning", "warnings"}],
          counts[status] > 0 do
        names = for result <- results, result.status == status, do: result.label || result.id
        "#{count(counts[status], singular, plural)}: #{Enum.join(names, ", ")}."
      end

    skipped = if counts.skipped > 0, do: " #{count(counts.skipped, "check", "checks")} skipped.", else: ""

    case problems do
      [] ->
        [:green, "All checks passed.", :reset, skipped, "\n"]

      problems ->
        details = if verbose?, do: [], else: [:faint, " Details: mix brando.doctor --verbose", :reset]
        [:blue, Enum.join(problems, " "), :reset, skipped, details, "\n"]
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
