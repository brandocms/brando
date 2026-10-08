defmodule Brando.Search.Highlight do
  @moduledoc """
  Turns a `ts_headline` snippet into segments that are safe to render.

  Postgres marks the matches with two control characters that indexed text
  never holds (`Brando.Search.Text.plain/1` removes them). The snippet is
  split on them into `{:text, string}` and `{:mark, string}` segments; the
  admin renders both as ordinary escaped text, a mark inside `<mark>`. No
  part of a snippet is ever treated as HTML.
  """

  @start <<2>>
  @stop <<3>>

  @type segment :: {:text | :mark, String.t()}

  @doc "The marker before a match."
  def start_marker, do: @start

  @doc "The marker after a match."
  def stop_marker, do: @stop

  @doc """
  The segments of a snippet. A marker without its pair is dropped, and so
  are empty segments.

      iex> Brando.Search.Highlight.segments("a \\u0002hit\\u0003 <b>")
      [{:text, "a "}, {:mark, "hit"}, {:text, " <b>"}]
  """
  @spec segments(String.t() | nil) :: [segment()]
  def segments(nil), do: []

  def segments(snippet) when is_binary(snippet) do
    snippet
    |> String.split(@start)
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {text, 0} -> [{:text, strip(text)}]
      {part, _} -> marked(String.split(part, @stop, parts: 2))
    end)
    |> Enum.reject(fn {_kind, text} -> text == "" end)
  end

  defp marked([mark, rest]), do: [{:mark, strip(mark)}, {:text, strip(rest)}]
  defp marked([text]), do: [{:text, strip(text)}]

  defp strip(text), do: String.replace(text, [@start, @stop], "")

  @doc "The snippet as plain text, without marks."
  @spec text([segment()]) :: String.t()
  def text(segments), do: Enum.map_join(segments, &elem(&1, 1))
end
