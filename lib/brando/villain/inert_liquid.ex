defmodule Brando.Villain.InertLiquid do
  @moduledoc """
  Makes HTML inert to a later Liquid pass (`Brando.Villain.parse_and_render/2`):
  braces become entities, which browsers show as the same text, so Liquid
  finds no delimiter.

  For HTML that must not be evaluated in this render: content from outside
  the CMS, and output a render has already evaluated. Script and style
  content is raw text, where entities stay literal, so it is left as it is.
  """

  @raw_text_elements ~r/<(script|style)(?=[\s>\/]).*?<\/\1\s*>/is

  def encode(nil), do: nil

  def encode(html) do
    html = IO.iodata_to_binary(html)

    if :binary.match(html, "{") == :nomatch, do: html, else: outside_raw_text(html, &encode_braces/1)
  end

  @doc """
  Every brace a character reference, script and style included: for a value
  on its own, which no template wrote and which could hold a whole script
  element. In script or style the references stay literal.
  """
  def encode_all(nil), do: nil
  def encode_all(html), do: html |> IO.iodata_to_binary() |> encode_braces()

  @doc """
  A template's dynamic output (`Brando.Villain.HeexRenderer`) and a filter's
  (`Brando.Villain.TemplateView.filter_result/4`): the Liquid delimiters in it
  character references, so what a value holds starts no Liquid,
  and any other brace as it is, so printed JSON stays JSON. A brace at the end
  could start one with what comes next.
  """
  def encode_delimiters(html) do
    html = IO.iodata_to_binary(html)

    if :binary.match(html, "{") == :nomatch,
      do: html,
      else: String.replace(html, ~r/\{(?=[{%]|\z)/, "&#123;")
  end

  @doc """
  The start of a value that follows a `{`, as a character reference where it
  would complete a Liquid delimiter.
  """
  def close_delimiter("{" <> rest), do: "&#123;" <> rest
  def close_delimiter("%" <> rest), do: "&#37;" <> rest
  def close_delimiter(text), do: text

  @doc """
  Plain braces again, for output no Liquid pass reads after it, such as a
  Markdown template's (`Brando.Villain.Markdown`).
  """
  def decode(nil), do: nil

  def decode(html) do
    outside_raw_text(
      html,
      &String.replace(&1, ["&#123;", "&#125;"], fn entity -> if entity == "&#123;", do: "{", else: "}" end)
    )
  end

  defp encode_braces(html),
    do: String.replace(html, ["{", "}"], fn brace -> if brace == "{", do: "&#123;", else: "&#125;" end)

  defp outside_raw_text(html, fun) do
    html
    |> IO.iodata_to_binary()
    |> then(&Regex.split(@raw_text_elements, &1, include_captures: true))
    |> Enum.with_index()
    |> Enum.map_join(fn
      {raw_text, index} when rem(index, 2) == 1 -> raw_text
      {markup, _} -> fun.(markup)
    end)
  end
end
