defmodule Brando.Villain.Tags.For do
  @moduledoc """
  `{% for name in collection %}`, as Liquid has it, keeping the text each
  escaped string of a collection the template reads stands for
  (`Brando.Villain.TemplateView.loop/4`).
  """
  @behaviour Liquex.Tag

  alias Brando.Villain.TemplateView

  @impl true
  defdelegate parse, to: Liquex.Tag.ForTag

  # The collection is a field, a literal or a range, with no filters: reading
  # it once more here runs nothing twice
  @impl true
  def render([identifier: name, collection: collection] ++ _rest = contents, context) do
    read? = TemplateView.read?(collection, context)
    {items, context} = Liquex.Argument.eval(collection, context)
    Liquex.Tag.ForTag.render(contents, TemplateView.loop(context, name, items, read?))
  end
end
