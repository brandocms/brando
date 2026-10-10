# Summarises the collector's traces.jsonl. See README.md.
#
#   elixir e2e/bench/otel/summary.exs [options] [traces.jsonl]
#
#   (default)        per span name: count, total, self time, p50, p95, max
#   --slow N         the N slowest traces as indented trees
#   --repeats        SQL statements run more than once within one trace
#   --root PATTERN   only traces whose root span name contains PATTERN
#   --since MINUTES  only traces that started in the last MINUTES
#   --from/--to UNIX only traces that started in this window (seconds)
#   --limit N        rows in the default table (default 40)
#   --exclude A,B    drop traces whose root span name contains A or B
#   --windows FILE   one row per window in FILE (TSV: label, start, end[, ...],
#                    as run-specs and traced-flows print): server busy time,
#                    queries, slowest trace and the top self-time spans
#   --json           with --windows: print JSON instead of text
#
# Self time is a span's duration minus its direct children's, so a LiveView
# event that spends its time in queries shows up under the queries.

defmodule Summary do
  def main(argv) do
    {opts, args, _} =
      OptionParser.parse(argv,
        strict: [
          slow: :integer,
          repeats: :boolean,
          root: :string,
          since: :integer,
          from: :integer,
          to: :integer,
          limit: :integer,
          windows: :string,
          json: :boolean,
          exclude: :string
        ]
      )

    path = List.first(args) || Path.expand("~/.local/share/brando-otel/traces.jsonl")

    spans = load(path)

    if opts[:windows] do
      windows(spans, opts)
    else
      spans
      |> filter(opts)
      |> report(opts)
    end
  end

  # Busy time is the sum of the window's root spans: LiveView callbacks and
  # renders run one at a time in the LiveView process, so their roots add up
  # to the time the editor's server side was occupied.
  defp windows(spans, opts) do
    spans = Enum.group_by(spans, & &1.trace)

    rows =
      opts[:windows]
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&String.split(&1, "\t"))
      |> Enum.map(fn [label, from, to | rest] ->
        traces = filter(spans, from: String.to_integer(from), to: String.to_integer(to), exclude: opts[:exclude])
        window(label, traces, List.first(rest))
      end)

    if opts[:json] do
      IO.puts(JSON.encode!(rows))
    else
      IO.puts(row(["busy ms", "queries", "traces", "max ms", "window"]))

      Enum.each(rows, fn r ->
        IO.puts(row([ms(r.busy_ms), r.queries, r.traces, ms(r.max_root_ms), r.label]))
        Enum.each(r.top_self, &IO.puts(String.duplicate(" ", 42) <> "#{ms(&1.ms)}ms #{&1.name}"))
      end)
    end
  end

  defp window(label, traces, result) do
    spans = traces |> Map.values() |> List.flatten()
    roots = traces |> Map.values() |> Enum.map(&root/1)

    %{
      label: label,
      result: result,
      traces: map_size(traces),
      busy_ms: roots |> Enum.map(& &1.ms) |> Enum.sum(),
      max_root_ms: roots |> Enum.map(& &1.ms) |> Enum.max(fn -> 0 end),
      max_root: roots |> Enum.max_by(& &1.ms, fn -> %{name: nil} end) |> Map.get(:name),
      queries: Enum.count(spans, &Map.has_key?(&1.attributes, "db.system")),
      top_self: self_times(spans) |> Enum.take(6) |> Enum.map(fn {name, self} -> %{name: name, ms: self} end),
      brando:
        spans
        |> Enum.filter(&String.starts_with?(&1.name, "brando."))
        |> Enum.group_by(& &1.name)
        |> Enum.map(fn {name, group} ->
          %{name: name, count: length(group), ms: group |> Enum.map(& &1.ms) |> Enum.sum()}
        end)
        |> Enum.sort_by(& &1.ms, :desc)
    }
  end

  defp self_times(spans) do
    child_ms = child_time(spans)

    spans
    |> Enum.group_by(&group_name/1)
    |> Enum.map(fn {name, group} -> {name, Enum.sum(Enum.map(group, &max(&1.ms - Map.get(child_ms, &1.id, 0), 0)))} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp load(path) do
    path
    |> File.stream!()
    |> Stream.flat_map(fn line -> line |> JSON.decode!() |> spans() end)
    |> Enum.to_list()
  end

  defp spans(%{"resourceSpans" => resource_spans}) do
    for %{"scopeSpans" => scope_spans} <- resource_spans,
        %{"spans" => spans} <- scope_spans,
        span <- spans do
      start = String.to_integer(span["startTimeUnixNano"])

      %{
        trace: span["traceId"],
        id: span["spanId"],
        parent: blank(span["parentSpanId"]),
        name: span["name"],
        start: start,
        ms: (String.to_integer(span["endTimeUnixNano"]) - start) / 1_000_000,
        attributes: Map.new(span["attributes"] || [], &{&1["key"], value(&1["value"])}),
        error: get_in(span, ["status", "code"]) == 2
      }
    end
  end

  defp blank(""), do: nil
  defp blank(value), do: value

  defp value(%{"stringValue" => v}), do: v
  defp value(%{"intValue" => v}), do: String.to_integer(v)
  defp value(%{"doubleValue" => v}), do: v
  defp value(%{"boolValue" => v}), do: v
  defp value(other), do: inspect(other)

  defp filter(spans, opts) when is_list(spans), do: filter(Enum.group_by(spans, & &1.trace), opts)

  defp filter(traces, opts) do
    from =
      cond do
        opts[:since] -> System.os_time(:nanosecond) - opts[:since] * 60_000_000_000
        opts[:from] -> opts[:from] * 1_000_000_000
        true -> 0
      end

    to = if opts[:to], do: opts[:to] * 1_000_000_000, else: :infinity

    traces
    |> Enum.filter(fn {_id, spans} ->
      root = root(spans)
      excluded = opts[:exclude] && String.contains?(root.name, String.split(opts[:exclude], ","))

      root.start >= from and root.start <= to and !excluded and
        (is_nil(opts[:root]) or String.contains?(root.name, opts[:root]))
    end)
    |> Map.new()
  end

  # A trace whose root was not exported (still open, or lost) roots at its
  # earliest span.
  defp root(spans), do: Enum.find(spans, &is_nil(&1.parent)) || Enum.min_by(spans, & &1.start)

  defp report(traces, opts) do
    cond do
      opts[:slow] -> slow(traces, opts[:slow])
      opts[:repeats] -> repeats(traces)
      true -> table(traces, opts[:limit] || 40)
    end
  end

  defp table(traces, limit) do
    spans = traces |> Map.values() |> List.flatten()
    child_ms = child_time(spans)

    IO.puts("#{map_size(traces)} traces, #{length(spans)} spans\n")
    IO.puts(row(["self ms", "total ms", "count", "p50", "p95", "max", "name"]))

    spans
    |> Enum.group_by(&group_name/1)
    |> Enum.map(fn {name, group} ->
      durations = group |> Enum.map(& &1.ms) |> Enum.sort()
      self = Enum.sum(Enum.map(group, &max(&1.ms - Map.get(child_ms, &1.id, 0), 0)))
      {self, Enum.sum(durations), length(group), pct(durations, 50), pct(durations, 95), List.last(durations), name}
    end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.take(limit)
    |> Enum.each(fn {self, total, count, p50, p95, max, name} ->
      IO.puts(row([ms(self), ms(total), count, ms(p50), ms(p95), ms(max), name]))
    end)
  end

  # A parent's time in its children, as the union of their intervals within
  # it: children can run in parallel (image sizes, async tasks), so summing
  # them would count the same time twice.
  defp child_time(spans) do
    by_id = Map.new(spans, &{&1.id, &1})

    spans
    |> Enum.filter(&Map.has_key?(by_id, &1.parent))
    |> Enum.group_by(& &1.parent)
    |> Map.new(fn {parent_id, children} -> {parent_id, covered(by_id[parent_id], children)} end)
  end

  defp covered(parent, children) do
    stop = parent.start + parent.ms * 1_000_000

    children
    |> Enum.map(&{max(&1.start, parent.start), min(&1.start + &1.ms * 1_000_000, stop)})
    |> Enum.filter(fn {from, to} -> to > from end)
    |> Enum.sort()
    |> Enum.reduce({0, nil}, fn
      interval, {total, nil} ->
        {total, interval}

      {from, to}, {total, {current_from, current_to}} when from <= current_to ->
        {total, {current_from, max(current_to, to)}}

      interval, {total, {current_from, current_to}} ->
        {total + (current_to - current_from), interval}
    end)
    |> then(fn
      {total, nil} -> total
      {total, {from, to}} -> total + (to - from)
    end)
    |> Kernel./(1_000_000)
  end

  # Ecto spans are named per table; group queries by source and command.
  defp group_name(%{attributes: %{"db.statement" => _} = attrs, name: name}) do
    "#{name} (#{attrs |> Map.get("db.statement", "") |> String.split(" ", parts: 2) |> hd()})"
  end

  defp group_name(span), do: span.name

  defp slow(traces, n) do
    traces
    |> Enum.map(fn {_id, spans} -> {root(spans), spans} end)
    |> Enum.sort_by(fn {root, _} -> root.ms end, :desc)
    |> Enum.take(n)
    |> Enum.each(fn {root, spans} ->
      children = Enum.group_by(spans, & &1.parent)
      IO.puts("")
      tree(root, children, 0)
    end)
  end

  defp tree(span, children, depth) do
    kids = children |> Map.get(span.id, []) |> Enum.sort_by(& &1.start)
    error = if span.error, do: " ERROR", else: ""
    IO.puts("#{String.duplicate("  ", depth)}#{ms(span.ms)}ms #{span.name}#{attrs(span)}#{error}")

    # Collapse runs of same-named siblings (per-block renders, repeated queries).
    kids
    |> Enum.chunk_by(& &1.name)
    |> Enum.each(fn
      [one] ->
        tree(one, children, depth + 1)

      [first | _] = run when length(run) > 3 ->
        total = run |> Enum.map(& &1.ms) |> Enum.sum()
        IO.puts("#{String.duplicate("  ", depth + 1)}#{ms(total)}ms #{length(run)}× #{first.name}")

      run ->
        Enum.each(run, &tree(&1, children, depth + 1))
    end)
  end

  defp attrs(%{attributes: attributes}) do
    case for {"brando." <> key, v} <- attributes, do: "#{key}=#{v}" do
      [] -> ""
      pairs -> " [" <> Enum.join(pairs, " ") <> "]"
    end
  end

  defp repeats(traces) do
    traces
    |> Enum.flat_map(fn {_id, spans} ->
      root = root(spans)

      spans
      |> Enum.filter(&Map.has_key?(&1.attributes, "db.statement"))
      |> Enum.frequencies_by(& &1.attributes["db.statement"])
      |> Enum.filter(fn {_statement, count} -> count > 1 end)
      |> Enum.map(fn {statement, count} -> {root.name, count, statement} end)
    end)
    |> Enum.group_by(fn {root, _count, statement} -> {root, statement} end, fn {_, count, _} -> count end)
    |> Enum.map(fn {{root, statement}, counts} -> {Enum.max(counts), length(counts), root, statement} end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.take(30)
    |> Enum.each(fn {max, traces, root, statement} ->
      IO.puts("#{max}× in one trace (#{traces} traces) under #{root}\n    #{String.slice(statement, 0, 200)}")
    end)
  end

  defp pct([], _), do: 0
  defp pct(sorted, p), do: Enum.at(sorted, min(length(sorted) - 1, trunc(length(sorted) * p / 100)))

  defp ms(value), do: :erlang.float_to_binary(value / 1, decimals: 1)

  defp row(cells) do
    {numbers, [name]} = Enum.split(cells, -1)
    Enum.map_join(numbers, " ", &String.pad_leading(to_string(&1), 9)) <> "  " <> to_string(name)
  end
end

Summary.main(System.argv())
