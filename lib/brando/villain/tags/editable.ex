defmodule Brando.Villain.Tags.Editable do
  @moduledoc """
  Makes an entry field editable in frontend edit mode where other markup
  shows it:

      {% editable entry.cover %}{% picture entry.cover %}{% endeditable %}

  The Liquid counterpart of `Brando.HTML.editable/1`. Outside edit mode it
  renders nothing of its own. See `Brando.FrontendEdit.Fields`.
  """
  @behaviour Liquex.Tag

  alias Brando.FrontendEdit.Fields
  alias Brando.Villain.LiquexParser.TagGrammar

  @stack :brando_editable

  @impl true
  def parse, do: TagGrammar.parse(:editable)

  @impl true
  def render([field: argument], context) do
    {entry, field, context} = resolve(argument, context)
    key = Fields.marker_key(entry, field)
    context = %{context | private: Map.update(context.private, @stack, [key], &[key | &1])}

    {[if(key, do: Fields.open(:markup, key), else: "")], context}
  end

  @doc false
  # Closes the innermost `{% editable %}`.
  def close(context) do
    case Map.get(context.private, @stack, []) do
      [key | rest] ->
        {[if(key, do: Fields.close(:markup, key), else: "")],
         %{context | private: Map.put(context.private, @stack, rest)}}

      [] ->
        {[""], context}
    end
  end

  @doc false
  # `entry.title` → the entry and `"title"`: the field is the last key of the
  # path, the entry everything before it.
  def resolve({:field, accesses}, context) when length(accesses) > 1 do
    case Enum.split(accesses, -1) do
      {parent, [{:key, name}]} ->
        {entry, context} = Liquex.Argument.eval({:field, parent}, context)
        {entry, Fields.field(entry, name), context}

      _ ->
        {nil, nil, context}
    end
  end

  def resolve(_argument, context), do: {nil, nil, context}
end
