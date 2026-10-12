defmodule Mix.Brando.Igniter.NodeRange do
  @moduledoc false
  # Reads an npm semver range, as in a package.json's `engines.node`, far
  # enough to tell whether it allows some release of a Node major version.
  # Versions are `{major, minor, patch}`; a bound is `{version, inclusive?}`.

  @operator ~r/^(>=|<=|>|<|=|~|\^)?v?(.*)$/

  @doc """
  `{:ok, true}` when some `major.x.y` satisfies `range`, `{:ok, false}`
  when none does, and `:error` when the range is not one this reads.
  """
  def allows_major?(range, major) when is_binary(range) and is_integer(major) do
    alternatives = range |> String.trim() |> String.split("||")

    alternatives
    |> Enum.reduce_while({:ok, false}, fn alternative, {:ok, allowed?} ->
      case bounds(alternative) do
        {:ok, {lower, upper}} -> {:cont, {:ok, allowed? or overlaps?(lower, upper, major)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp overlaps?(lower, upper, major) do
    lower = max_lower(lower, {{major, 0, 0}, true})
    upper = min_upper(upper, {{major + 1, 0, 0}, false})
    non_empty?(lower, upper)
  end

  defp non_empty?({low, low_inclusive?}, {high, high_inclusive?}),
    do: low < high or (low == high and low_inclusive? and high_inclusive?)

  # A range is comparators separated by spaces, or `a - b`.
  defp bounds(alternative) do
    alternative = Regex.replace(~r/(>=|<=|>|<|=|~|\^)\s+/, String.trim(alternative), "\\1")

    case String.split(alternative, ~r/\s+-\s+/) do
      [from, to] ->
        with {:ok, from} <- partial(from), {:ok, to} <- partial(to) do
          {:ok, {lower_from(from), upper_through(to)}}
        end

      [_comparators] ->
        alternative
        |> String.split(~r/\s+/, trim: true)
        |> Enum.reduce_while({:ok, {{{0, 0, 0}, true}, nil}}, &intersect/2)
    end
  end

  defp intersect(comparator, {:ok, {lower, upper}}) do
    case comparator(comparator) do
      {:ok, {comparator_lower, comparator_upper}} ->
        {:cont, {:ok, {max_lower(lower, comparator_lower), min_upper(upper, comparator_upper)}}}

      :error ->
        {:halt, :error}
    end
  end

  defp comparator(text) do
    [_, operator, version] = Regex.run(@operator, text)

    with {:ok, parts} <- partial(version) do
      {:ok, comparator_bounds(operator, parts)}
    end
  end

  defp comparator_bounds(_operator, []), do: {nil, nil}
  defp comparator_bounds(">=", parts), do: {lower_from(parts), nil}
  defp comparator_bounds(">", [_, _, _] = parts), do: {{fill(parts), false}, nil}
  defp comparator_bounds(">", parts), do: {{next(parts), true}, nil}
  defp comparator_bounds("<", parts), do: {nil, {fill(parts), false}}
  defp comparator_bounds("<=", parts), do: {nil, upper_through(parts)}
  defp comparator_bounds("~", [major]), do: {lower_from([major]), {next([major]), false}}
  defp comparator_bounds("~", [major, minor | _] = parts), do: {lower_from(parts), {next([major, minor]), false}}
  defp comparator_bounds("^", [0 | _] = parts), do: comparator_bounds("~", parts)
  defp comparator_bounds("^", [major | _] = parts), do: {lower_from(parts), {next([major]), false}}
  defp comparator_bounds(_exact, parts), do: {lower_from(parts), upper_through(parts)}

  defp lower_from([]), do: nil
  defp lower_from(parts), do: {fill(parts), true}

  defp upper_through([]), do: nil
  defp upper_through([_, _, _] = parts), do: {fill(parts), true}
  defp upper_through(parts), do: {next(parts), false}

  # "22", "22.x", "22.1.2-rc.1": the numeric parts given, up to the first wildcard.
  defp partial(version) do
    numbers =
      version
      |> String.split(["-", "+"], parts: 2)
      |> hd()
      |> String.split(".")
      |> Enum.take_while(&(&1 not in ["x", "X", "*", ""]))
      |> Enum.map(&Integer.parse/1)

    if Enum.all?(numbers, &match?({_number, ""}, &1)) and Enum.count(numbers) <= 3,
      do: {:ok, Enum.map(numbers, &elem(&1, 0))},
      else: :error
  end

  defp fill(parts), do: parts |> Kernel.++([0, 0, 0]) |> Enum.take(3) |> List.to_tuple()

  defp next(parts), do: parts |> List.update_at(-1, &(&1 + 1)) |> fill()

  defp max_lower(nil, other), do: other
  defp max_lower(other, nil), do: other
  defp max_lower({a, _} = first, {b, _}) when a > b, do: first
  defp max_lower({a, a_inclusive?}, {a, b_inclusive?}), do: {a, a_inclusive? and b_inclusive?}
  defp max_lower(_first, second), do: second

  defp min_upper(nil, other), do: other
  defp min_upper(other, nil), do: other
  defp min_upper({a, _} = first, {b, _}) when a < b, do: first
  defp min_upper({a, a_inclusive?}, {a, b_inclusive?}), do: {a, a_inclusive? and b_inclusive?}
  defp min_upper(_first, second), do: second
end
