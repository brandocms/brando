defmodule Brando.Villain.Tags.Ref do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag

  @impl true
  def parse() do
    ignore(Tag.open_tag())
    |> ignore(string("ref"))
    |> ignore(Literal.whitespace())
    |> unwrap_and_tag(Argument.argument(), :ref)
    |> ignore(Tag.close_tag())
  end

  @impl true
  def render([ref: ref], context) do
    {:field, [_ | [{:key, ref_name}]]} = ref
    brando_render_for_admin = Map.get(context, :brando_render_for_admin)
    evaled_ref = Liquex.Argument.eval(ref, context)

    rendered_ref =
      render_ref(
        context.variables.brando_parser_module,
        evaled_ref,
        context.variables.brando_module_id,
        ref_name,
        brando_render_for_admin
      )

    {rendered_ref, context}
  end

  defp render_ref(_, nil, id, ref_name, _),
    do: "<!-- REF #{ref_name} missing // module: #{id}. -->"

  defp render_ref(_, %{hidden: true}, _id, _ref_name, _), do: "<!-- h -->"
  defp render_ref(_, %{data: %{hidden: true}}, _id, _ref_name, _), do: "<!-- h -->"
  defp render_ref(_, %{deleted: true}, _id, _ref_name, _), do: "<!-- d -->"

  defp render_ref(parser, %{data: block, description: description}, id, ref_name, true) do
    rendered_ref = apply(parser, String.to_atom(block.type), [block.data, []])

    """
    <section phx-click="edit_ref" b-module-id="#{id}" b-ref="#{ref_name}" b-ref-desc="#{description}">
      #{rendered_ref}
    </section>
    """
  end

  defp render_ref(parser, %{data: block, description: _description}, _id, _ref_name, _) do
    apply(parser, String.to_atom(block.type), [block.data, []])
  end
end
