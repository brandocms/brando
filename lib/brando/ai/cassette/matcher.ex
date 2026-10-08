defmodule Brando.AI.Cassette.Matcher do
  @moduledoc """
  Decides whether a recorded request answers a new one.

  `match_on:` lists what must be equal, as names or functions:

    * `:kind` — `generate_text` or `stream_text`, always checked;
    * `:model` — the `"provider:model"` spec;
    * `:system` — the system prompt;
    * `:messages` — the conversation, after normalisation;
    * `:last_message` — only the newest message;
    * `:tools` — tool names and a digest of their definitions;
    * `:tool_names` — tool names only;
    * `:params` — `max_tokens`, `temperature` and the other model parameters;
    * a function of two arguments, the recorded and the new normalised
      request (see `Brando.AI.Cassette.Request`), returning a boolean.

  The default is `[:model, :system, :messages, :tools, :params]`.
  """

  alias Brando.AI.Cassette.MismatchError

  @default [:model, :system, :messages, :tools, :params]
  @diff_limit 8

  @doc "The default `match_on:` list."
  def default, do: @default

  @doc "Whether `recorded` answers `request` under `match_on`."
  @spec match?(map(), map(), list()) :: boolean()
  def match?(recorded, request, match_on) do
    recorded["kind"] == request["kind"] and Enum.all?(match_on, &same?(&1, recorded, request))
  end

  defp same?(fun, recorded, request) when is_function(fun, 2), do: fun.(recorded, request) == true

  defp same?(:last_message, recorded, request),
    do: List.last(recorded["messages"] || []) == List.last(request["messages"] || [])

  defp same?(:tool_names, recorded, request), do: names(recorded) == names(request)
  defp same?(key, recorded, request) when is_atom(key), do: recorded[to_string(key)] == request[to_string(key)]

  defp names(request), do: Enum.map(request["tools"] || [], & &1["name"])

  @doc "The error for a request no unused interaction matches."
  @spec mismatch(map(), map()) :: MismatchError.t()
  def mismatch(state, request) do
    indexed = Enum.with_index(state.interactions)
    used = Enum.find(indexed, fn {i, index} -> index in state.used and match?(i["request"], request, state.match_on) end)
    unused = Enum.reject(indexed, fn {_, index} -> index in state.used end)

    closest =
      unused
      |> Enum.map(fn {interaction, index} -> {index, diff(interaction["request"], request)} end)
      |> Enum.min_by(fn {_, diffs} -> length(diffs) end, fn -> nil end)

    %MismatchError{
      cassette: state.name,
      path: state.path,
      match_on: state.match_on,
      request: request,
      replayed: used && elem(used, 1),
      closest: closest,
      interactions: length(state.interactions)
    }
  end

  @doc """
  The differences between two normalised requests, as
  `{path, recorded, actual}`, at most #{@diff_limit}.
  """
  @spec diff(term(), term()) :: [{String.t(), term(), term()}]
  def diff(recorded, actual), do: recorded |> diff(actual, "") |> Enum.take(@diff_limit)

  defp diff(same, same, _path), do: []

  defp diff(%{} = recorded, %{} = actual, path) do
    (Map.keys(recorded) ++ Map.keys(actual))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(&diff(Map.get(recorded, &1), Map.get(actual, &1), join(path, &1)))
  end

  defp diff(recorded, actual, path) when is_list(recorded) and is_list(actual) do
    if length(recorded) == length(actual) do
      recorded
      |> Enum.zip(actual)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{r, a}, i} -> diff(r, a, "#{path}[#{i}]") end)
    else
      [{path <> " (length)", length(recorded), length(actual)} | first_list_diff(recorded, actual, path)]
    end
  end

  defp diff(recorded, actual, path), do: [{path, recorded, actual}]

  defp first_list_diff(recorded, actual, path) do
    recorded
    |> Enum.zip(actual)
    |> Enum.with_index()
    |> Enum.find_value([], fn {{r, a}, i} -> if r != a, do: diff(r, a, "#{path}[#{i}]") end)
  end

  defp join("", key), do: to_string(key)
  defp join(path, key), do: "#{path}.#{key}"
end
