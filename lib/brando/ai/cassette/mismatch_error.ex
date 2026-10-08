defmodule Brando.AI.Cassette.MismatchError do
  @moduledoc """
  A model request that no recorded interaction in the cassette answers.

  Returned to the code that made the request, as a provider error would be,
  and raised again when the cassette is checked at the end of the test, so
  the test fails with this message even when the request was made in a
  LiveView or a task.
  """

  @type t :: %__MODULE__{}

  defexception [:cassette, :path, :match_on, :request, :replayed, :closest, interactions: 0]

  @impl true
  def message(%__MODULE__{} = error) do
    [
      "cassette #{inspect(error.cassette)} has no recorded request that matches this one " <>
        "(matching on #{Enum.map_join(error.match_on, ", ", &describe/1)}).",
      replayed(error),
      closest(error),
      "The request (long text shortened):\n" <> indent(pretty(shorten(error.request))),
      hint(error)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp replayed(%{replayed: nil}), do: nil

  defp replayed(%{replayed: index}),
    do: "It matches interaction ##{index + 1}, which this test has already played. Record the repeated call too."

  defp closest(%{closest: nil, interactions: 0}), do: "The cassette has no interactions."
  defp closest(%{closest: nil}), do: "Every recorded interaction has been played."

  defp closest(%{closest: {index, diffs}}) do
    lines =
      Enum.map_join(diffs, "\n", fn {path, recorded, actual} ->
        "  #{path}:\n    recorded: #{short(recorded)}\n    got:      #{short(actual)}"
      end)

    "The closest unplayed interaction is ##{index + 1}. It differs at:\n" <> lines
  end

  defp hint(%{path: nil}), do: nil

  defp hint(%{path: path}) do
    "Record it again with BRANDO_CASSETTE_MODE=record (calls the real model, so it needs a key), " <>
      "or edit #{Path.relative_to_cwd(path)}."
  end

  defp describe(fun) when is_function(fun), do: "a custom matcher"
  defp describe(key), do: to_string(key)

  defp short(value) do
    text = if is_binary(value), do: inspect(value), else: value |> pretty() |> String.replace(~r/\s+/, " ")
    if String.length(text) > 300, do: String.slice(text, 0, 300) <> "…", else: text
  end

  defp pretty(term), do: term |> Brando.AI.Cassette.Request.ordered() |> Jason.encode!(pretty: true)

  defp shorten(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, shorten(value)} end)
  defp shorten(list) when is_list(list), do: Enum.map(list, &shorten/1)
  defp shorten(text) when is_binary(text) and byte_size(text) > 400, do: String.slice(text, 0, 400) <> "…"
  defp shorten(other), do: other

  defp indent(text), do: text |> String.split("\n") |> Enum.map_join("\n", &("  " <> &1))
end
