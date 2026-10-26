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
    html
    |> IO.iodata_to_binary()
    |> then(&Regex.split(@raw_text_elements, &1, include_captures: true))
    |> Enum.with_index()
    |> Enum.map_join(fn
      {raw_text, index} when rem(index, 2) == 1 -> raw_text
      {markup, _} -> String.replace(markup, ["{", "}"], &if(&1 == "{", do: "&#123;", else: "&#125;"))
    end)
  end
end
