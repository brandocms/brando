defmodule Brando.Villain.Tags.Ref do
  @moduledoc false
  @behaviour Liquex.Tag

  alias Brando.Villain.InertLiquid
  alias Brando.Villain.LiquexParser.TagGrammar
  alias Brando.Villain.RenderSourceQuery
  alias Brando.Villain.TemplateView
  alias Ecto.Changeset

  @brando_env Application.compile_env(:brando, :env)
  @module_cache_ttl (@brando_env == :e2e && %{}) || %{cache: {:ttl, :infinite}}
  @container_cache_ttl (@brando_env == :e2e && %{}) || %{cache: {:ttl, :infinite}}
  @palette_cache_ttl (@brando_env == :e2e && %{}) || %{cache: {:ttl, :infinite}}

  @impl true
  def parse, do: TagGrammar.parse(:ref)

  @impl true
  def render([ref: ref], context) do
    {:field, [_ | [{:key, ref_name}]]} = ref
    brando_render_for_admin = Access.get(context, :brando_render_for_admin)
    evaled_ref = TemplateView.eval(ref, context)

    {:ok, modules} = RenderSourceQuery.list_modules(@module_cache_ttl)
    {:ok, containers} = RenderSourceQuery.list_containers(@container_cache_ttl)
    {:ok, palettes} = RenderSourceQuery.list_palettes(@palette_cache_ttl)

    opts_map =
      %{}
      |> Map.put(:context, context)
      |> Map.put(:containers, containers)
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

  defp render_ref(_, %{hidden: true}, _id, ref_name, _, _), do: "<!-- h[[#{ref_name}]] -->"
  defp render_ref(_, %{data: %{hidden: true}}, _id, ref_name, _, _), do: "<!-- h[#{ref_name}] -->"

  defp render_ref(_, %{deleted: true}, _id, _ref_name, _, _), do: "<!-- d -->"
  defp render_ref(_, %{active: false}, _id, ref_name, _, _), do: "<!-- !a[#{ref_name}] -->"

  defp render_ref(parser, %{data: block, description: description}, id, ref_name, true, opts) do
    rendered_ref = render_block_data(parser, block, opts)

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
    render_block_data(parser, block, opts)
  end

  defp render_ref(parser, %{data: block, description: _description}, _id, _ref_name, _, opts) do
    render_block_data(parser, block, opts)
  end

  # What a ref renders is text to the entry's final Liquid pass, however its
  # parser made it, alt attributes and a project's own parser included. An SVG
  # or HTML ref is a superuser's template, and a slot holds modules' and
  # containers' output. A Markdown render has no final pass.
  defp render_block_data(Brando.Villain.Markdown = parser, block, opts),
    do: apply(parser, parser_function(parser, block.type), [block.data, opts])

  defp render_block_data(parser, %{type: type} = block, opts) when type in ~w(svg html blocks),
    do: apply(parser, parser_function(parser, type), [block.data, opts])

  defp render_block_data(parser, block, opts) do
    parser
    |> apply(parser_function(parser, block.type), [block.data, opts])
    |> InertLiquid.encode()
  end

  @doc false
  # The block's type names the parser function. It is stored data, so it
  # must name one that exists; the parser is loaded first so its names are.
  def parser_function(parser, type) do
    Code.ensure_loaded(parser)
    String.to_existing_atom(type)
  end
end
