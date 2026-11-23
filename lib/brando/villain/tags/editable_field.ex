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
        {html, kind} = print(entry, field, rich)
        # Liquid in the field is text to the entry's final pass
        {[Fields.wrap(InertLiquid.encode_all(html), entry, field, kind)], context}

      {_other, _field, _rich, context} ->
        # Not an entry field: print the value escaped.
        value = TemplateView.eval_typed(argument, context)
        {[value |> printable() |> Brando.Villain.Parser.escape_var_value()], context}
    end
  end

  # A record prints by its own forms, a subform row read through its owner by
  # the owner's forms, as `{{ }}` prints it. Its markers say which rule, so
  # the frontend editor updates the page by it as the field is edited.
  defp print(entry, field, nil), do: {Fields.render_value(entry, field), :value}

  defp print(entry, field, rich),
    do: {Fields.render_value(entry, field, rich), if(field in rich, do: :rich_text, else: :text)}

  defp printable(nil), do: ""
  defp printable(value) when is_binary(value), do: value
  defp printable(value), do: if(String.Chars.impl_for(value), do: to_string(value), else: "")
end
