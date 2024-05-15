defmodule Brando.Villain.Tags.Ref do
  @moduledoc false
  @behaviour Liquex.Tag

  import NimbleParsec
  alias Ecto.Changeset
  alias Liquex.Parser.Argument
  alias Liquex.Parser.Literal
  alias Liquex.Parser.Tag
  alias Brando.Content

  @module_cache_ttl (Brando.config(:env) == :e2e && %{}) || %{cache: {:ttl, :infinite}}
  @palette_cache_ttl (Brando.config(:env) == :e2e && %{}) || %{cache: {:ttl, :infinite}}

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
    brando_render_for_admin = Access.get(context, :brando_render_for_admin)
    evaled_ref = Liquex.Argument.eval(ref, context)

    {:ok, modules} = Content.list_modules(@module_cache_ttl)
    {:ok, palettes} = Content.list_palettes(@palette_cache_ttl)

    opts_map =
      %{}
      |> Map.put(:context, context)
      |> Map.put(:modules, modules)
      |> Map.put(:palettes, palettes)

    rendered_ref =
      render_ref(
        Access.get(context, :brando_parser_module),
        evaled_ref,
        Access.get(context, :brando_module_id),
        ref_name,
        brando_render_for_admin,
        opts_map
      )

    {rendered_ref, context}
  end

  defp render_ref(_, nil, id, ref_name, _, _),
    do: "<!-- REF #{ref_name} missing // module: #{id}. -->"

  defp render_ref(_, %{hidden: true}, _id, _ref_name, _, _), do: "<!-- h -->"
  defp render_ref(_, %{data: %{hidden: true}}, _id, _ref_name, _, _), do: "<!-- h -->"
  defp render_ref(_, %{deleted: true}, _id, _ref_name, _, _), do: "<!-- d -->"

  defp render_ref(parser, %{data: block, description: description}, id, ref_name, true, opts) do
    rendered_ref = apply(parser, String.to_atom(block.type), [block.data, opts])

    """
    <section phx-click="edit_ref" b-module-id="#{id}" b-ref="#{ref_name}" b-ref-desc="#{description}">
      #{rendered_ref}
    </section>
    """
  end

  defp render_ref(
         parser,
         %{data: %Changeset{} = block_cs, description: _description},
         _id,
         _ref_name,
         _,
         opts
       ) do
    block = Changeset.apply_changes(block_cs)
    apply(parser, String.to_atom(block.type), [block.data, opts])
  end

  defp render_ref(parser, %{data: block, description: _description}, _id, _ref_name, _, opts) do
    apply(parser, String.to_atom(block.type), [block.data, opts])
  end
end
