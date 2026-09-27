defmodule BrandoAdmin.Components.Form.Visibility do
  @moduledoc """
  Whether a form input is shown, from its `hidden:` and `show_if:` options.

    * `hidden: true` — never shown (the value still round-trips if the form
      carries it elsewhere).
    * `hidden: {:kind, :pdf}` — hidden while the `kind` field is `:pdf`.
      The value can be a list: `{:kind, [:pdf, :audio]}` hides for either.
    * `hidden: &fun/1` — hidden when the function, given the form, returns
      `true`.
    * `show_if: {:kind, [:pdf, :audio]}` — the other way round: shown only
      while `kind` is one of those.

  The same rules apply to top-level fields, subform rows and transformer
  entries; the form passed in is the one the input belongs to.
  """

  alias Phoenix.HTML.FormField

  @doc "Whether an input with these options is hidden in `form`."
  def hidden?(opts, form) do
    opts = opts || []
    hidden_by?(Keyword.get(opts, :hidden), form) or not shown_by?(Keyword.get(opts, :show_if), form)
  end

  defp hidden_by?(nil, _form), do: false
  defp hidden_by?(hidden, _form) when is_boolean(hidden), do: hidden
  defp hidden_by?({field, expected}, form), do: field_matches?(form, field, expected)
  defp hidden_by?(fun, form) when is_function(fun, 1), do: safely(fn -> fun.(form) == true end)
  defp hidden_by?(_, _form), do: false

  defp shown_by?(nil, _form), do: true
  defp shown_by?({field, expected}, form), do: field_matches?(form, field, expected)
  defp shown_by?(_, _form), do: true

  defp field_matches?(form, field, expected) do
    safely(fn ->
      with {:ok, field} <- normalize_field(field),
           %FormField{value: value} <- form[field] do
        expected |> List.wrap() |> Enum.any?(&equivalent?(value, &1))
      else
        _ -> false
      end
    end)
  end

  defp safely(fun) do
    fun.()
  rescue
    _ -> false
  end

  defp normalize_field(field) when is_atom(field), do: {:ok, field}

  defp normalize_field(field) when is_binary(field) do
    {:ok, String.to_existing_atom(field)}
  rescue
    ArgumentError -> :error
  end

  defp normalize_field(_), do: :error

  defp equivalent?(left, right) when left === right, do: true
  defp equivalent?(left, right) when is_atom(left) and is_binary(right), do: Atom.to_string(left) == right
  defp equivalent?(left, right) when is_binary(left) and is_atom(right), do: left == Atom.to_string(right)
  defp equivalent?(_, _), do: false
end
