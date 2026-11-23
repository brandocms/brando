defmodule Brando.Villain.Tags.EditableField do
  @moduledoc """
  Prints an entry field, editable in place in frontend edit mode:

      <h2>{% editable_field entry.title %}</h2>

  The Liquid counterpart of `Brando.HTML.editable_field/1`. Use it where the
  value shows as text, not inside an attribute. Outside edit mode it prints
  the value and nothing else. See `Brando.FrontendEdit.Fields`.
  """
  @behaviour Liquex.Tag

  alias Brando.FrontendEdit.Fields
  alias Brando.Villain.InertLiquid
  alias Brando.Villain.LiquexParser.TagGrammar
  alias Brando.Villain.TemplateView

  @impl true
  def parse, do: TagGrammar.parse(:editable_field)

  @impl true
  def render([field: argument], context) do
    case Brando.Villain.Tags.Editable.resolve_with_rule(argument, context) do
      {%{__struct__: _} = entry, field, rich, context} when is_atom(field) and not is_nil(field) ->
        # Liquid in the field is text to the entry's final pass
        html = entry |> render_value(field, rich) |> InertLiquid.encode_all()
        {[Fields.wrap(html, entry, field, :value)], context}

      {_other, _field, _rich, context} ->
        # Not an entry field: print the value escaped.
        value = TemplateView.eval_typed(argument, context)
        {[value |> printable() |> Brando.Villain.Parser.escape_var_value()], context}
    end
  end

  # A subform row read through its owner prints by the owner's forms, a
  # record of its own by its own, as `{{ }}` prints it
  defp render_value(entry, field, nil), do: Fields.render_value(entry, field)
  defp render_value(entry, field, rich), do: Fields.render_value(entry, field, rich)

  defp printable(nil), do: ""
  defp printable(value) when is_binary(value), do: value
  defp printable(value), do: if(String.Chars.impl_for(value), do: to_string(value), else: "")
end
