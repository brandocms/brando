defmodule BrandoAdmin.Components.Form.Input.Options do
  @moduledoc """
  Shared expansion of the symbolic `:options` tokens a form input can declare.

  `input :language, :select, options: :languages` is resolved at render time,
  because the language lists come from config and Brando supports changing them
  at runtime (`Brando.RuntimeConfig`) — so this deliberately does NOT memoize.

  It lived in three places (`Input.radios/1`, `Input.Select`,
  `Input.MultiSelect`) as three byte-identical `case` arms, which is how
  `radios/1` came to be the only one of the three whose caller never cached the
  result. Keeping the expansion in one place does not fix that on its own, but
  it means the next reader sees one contract instead of three copies.
  """

  @tokens [:languages, :admin_languages]

  @doc "The `:options` tokens this module expands."
  def tokens, do: @tokens

  @doc """
  Expand `:languages` / `:admin_languages` into `%{label:, value:}` maps.

  Both config keys hold `[[value: "en", text: "English"], …]`.
  """
  def expand(token) when token in @tokens do
    token
    |> Brando.config()
    |> Enum.map(fn [{:value, value}, {:text, text}] -> %{label: text, value: value} end)
  end

  def expand(other), do: other
end
