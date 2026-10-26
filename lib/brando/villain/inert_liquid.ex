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
    outside_raw_text(html, &String.replace(&1, ["{", "}"], fn brace -> if brace == "{", do: "&#123;", else: "&#125;" end))
  end

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
