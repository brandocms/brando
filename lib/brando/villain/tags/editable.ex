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
  alias Brando.Villain.TemplateView

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

  @doc """
  Closes the innermost `{% editable %}`, popping its key from the render context.
  `{% endeditable %}` renders through this.
  """
  def close(context) do
    case Map.get(context.private, @stack, []) do
      [key | rest] ->
        {[if(key, do: Fields.close(:markup, key), else: "")],
         %{context | private: Map.put(context.private, @stack, rest)}}

      [] ->
        {[""], context}
    end
  end

  @doc """
  Resolves a Liquid field path to `{entry, field, context}`: `entry.title` gives the
  entry and `"title"`, since the field is the last key of the path and the entry
  everything before it. Returns `{nil, nil, context}` for any other argument.
  """
  def resolve(argument, context) do
    {entry, field, _rich, context} = resolve_with_rule(argument, context)
    {entry, field, context}
  end

  @doc """
  `resolve/2`, with the fields the entry prints as rich text by its owner's
  forms when it is a subform row read through its owner, else nil
  (`Brando.Villain.TemplateView.eval_record/2`).
  """
  def resolve_with_rule({:field, [_, _ | _] = accesses}, context) do
    case Enum.split(accesses, -1) do
      {parent, [{:key, name}]} ->
        {entry, rich} = TemplateView.eval_record({:field, parent}, context)
        {entry, Fields.field(entry, name), rich, context}

      _ ->
        {nil, nil, nil, context}
    end
  end

  def resolve_with_rule(_argument, context), do: {nil, nil, nil, context}
end
