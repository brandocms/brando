defmodule Brando.Villain.TemplateAdapter.Liquex do
  @moduledoc """
  Liquex (Liquid) template adapter for Villain modules and containers.

  Extracts the Liquex-specific rendering logic from `Brando.Villain.Parser`,
  building a `Liquex.Context` and delegating to `Brando.Villain.parse_and_render/2`.
  """

  @behaviour Brando.Villain.TemplateAdapter

  alias Brando.Villain
  alias Liquex.Context

  @impl true
  def render_module(module, block, processed_vars, processed_refs, opts) do
    base_context = opts.context

    context =
      base_context
      |> add_vars_to_context(processed_vars)
      |> add_refs_to_context(processed_refs)
      |> add_admin_to_context(opts)
      |> add_parser_to_context(opts)
      |> add_module_id_to_context(block.module_id)
      |> add_datasource_entries_to_context(module, block)
      |> add_block_to_context(module, block)

    module.code
    |> Villain.parse_and_render(context)
  end

  @impl true
  def render_multi_module(module, block, base_vars, base_refs, children, content, opts) do
    base_context = opts.context

    context =
      base_context
      |> add_vars_to_context(base_vars)
      |> add_refs_to_context(base_refs)
      |> add_admin_to_context(opts)
      |> add_parser_to_context(opts)
      |> add_module_id_to_context(block.module_id)
      |> add_block_to_context(module, block)
      |> Context.assign("entries", children)
      |> Context.assign("content", content)

    module.code
    |> Villain.parse_and_render(context)
  end

  @impl true
  def render_child_module(child_module, child_block, vars, refs, forloop, parent_module_id, opts) do
    base_context = opts.context

    context =
      base_context
      |> add_vars_to_context(vars)
      |> add_refs_to_context(refs)
      |> add_admin_to_context(opts)
      |> add_parser_to_context(opts)
      |> add_module_id_to_context(parent_module_id)
      |> add_block_to_context(child_module, child_block)
      |> Context.assign("forloop", forloop)

    Villain.parse_and_render(child_module.code, context)
  end

  @impl true
  def render_container(container, children_html, _block, _opts) do
    container.code
    |> String.replace("{{ content }}", children_html)
    |> Brando.Villain.Parser.replace_fragments()
  end

  # -- Context helpers --

  defp add_vars_to_context(context, vars),
    do: Enum.reduce(vars, context, fn {k, v}, acc -> Context.assign(acc, k, v) end)

  defp add_refs_to_context(context, refs),
    do: Context.assign(context, :refs, refs)

  defp add_admin_to_context(context, opts) do
    if Map.get(opts, :brando_render_for_admin) do
      Context.assign(context, :brando_render_for_admin, true)
    else
      context
    end
  end

  defp add_parser_to_context(context, opts),
    do: Context.assign(context, :brando_parser_module, opts[:parser_module] || Brando.Villain.Parser)

  defp add_module_id_to_context(context, module_id),
    do: Context.assign(context, :brando_module_id, module_id)

  defp add_block_to_context(context, module, block) do
    simple_block =
      block
      |> Map.take([
        :uid,
        :type,
        :module_id,
        :sequence,
        :active,
        :collapsed,
        :table_rows,
        :anchor,
        :description
      ])
      |> Map.merge(%{class: module.class})

    Context.assign(context, :block, simple_block)
  end

  defp add_datasource_entries_to_context(
         context,
         %{
           datasource: true,
           datasource_type: :list,
           datasource_module: module,
           datasource_query: query
         },
         %{vars: vars}
       ) do
    language = Context.get(context, "language")
    request = Context.get(context, "request")

    mapped_vars =
      vars
      |> map_vars()
      |> Map.merge(%{"request" => request})

    {:ok, entries} = Brando.Datasource.list_results(module, query, mapped_vars, language)

    Context.assign(context, :entries, entries || [])
  end

  defp add_datasource_entries_to_context(
         context,
         %{
           datasource: true,
           datasource_type: :selection,
           datasource_module: module,
           datasource_query: query
         },
         block
       ) do
    identifier_ids = Enum.map(block.block_identifiers, & &1.identifier_id)
    {:ok, entries} = Brando.Datasource.get_selection(module, query, identifier_ids)
    entries_with_meta = Brando.Villain.Parser.add_meta_to_entries(entries, block)

    context
    |> Context.assign(:entries, entries || [])
    |> Context.assign(:entries_with_meta, entries_with_meta || [])
  end

  defp add_datasource_entries_to_context(context, _, _),
    do: Context.assign(context, :entries, [])

  defp map_vars(nil), do: %{}
  defp map_vars(%Ecto.Association.NotLoaded{}), do: %{}

  defp map_vars(vars) do
    Map.new(vars, fn var -> {var.key, var.value} end)
  end
end
