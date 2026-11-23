defmodule Brando.Villain.Tags.Assign do
  @moduledoc """
  `{% assign name = value %}`, as Liquid has it, keeping the text an escaped
  value stands for (`Brando.Villain.TemplateView.assign/4`).
  """
  @behaviour Liquex.Tag

  alias Brando.Villain.TemplateView
  alias Liquex.Render

  @impl true
  defdelegate parse, to: Liquex.Tag.AssignTag

  @impl true
  def render([left: name, right: [right, filters: filters]], context) when is_binary(name) do
    {value, context} = Liquex.Argument.eval(right, context)
    {value, context} = Render.apply_filters(value, filters, context)
    {[], TemplateView.assign(context, name, value, match?({:field, _}, right))}
  end
end
