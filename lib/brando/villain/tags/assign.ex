defmodule Brando.Villain.Tags.Assign do
  @moduledoc """
  `{% assign name = value %}`, as Liquid has it. A tag reads text assigned
  so as it reads the field itself (`Brando.Villain.TemplateView.assign/3`).
  """
  @behaviour Liquex.Tag

  alias Brando.Villain.TemplateView
  alias Liquex.Render

  @impl true
  defdelegate parse, to: Liquex.Tag.AssignTag

  @impl true
  def render([left: name, right: [right, filters: filters]], context) when is_binary(name) do
    context =
      TemplateView.assign(context, name, fn context ->
        {value, context} = Liquex.Argument.eval(right, context)
        Render.apply_filters(value, filters, context)
      end)

    {[], context}
  end
end
