defmodule Brando.Villain.TemplateAdapter.Heex do
  @moduledoc """
  HEEx template adapter for Villain modules and containers.

  Builds an assigns map (vars at top level + system assigns) and
  delegates to `Brando.Villain.HeexRenderer` for compilation and rendering.
  """

  @behaviour Brando.Villain.TemplateAdapter

  alias Brando.Villain.HeexRenderer

  @context_assign_defaults %{
    configs: %{},
    entry: nil,
    globals: %{},
    identity: %{},
    language: nil,
    links: %{},
    locale: nil,
    navigation: %{},
    request: nil,
    url: nil
  }

  @impl true
  def render_module(module, block, processed_vars, processed_refs, opts) do
    assigns = build_assigns(module, block, processed_vars, processed_refs, opts)
    assigns = maybe_add_datasource_entries(assigns, module, block)

    HeexRenderer.render_to_string(module.id, module.code, assigns)
  end

  @impl true
  def render_multi_module(module, block, base_vars, base_refs, children, content, opts) do
    assigns =
      build_assigns(module, block, base_vars, base_refs, opts)
      |> Map.put(:entries, children)
      |> Map.put(:content, content)

    HeexRenderer.render_to_string(module.id, module.code, assigns)
  end

  @impl true
  def render_child_module(child_module, child_block, vars, refs, forloop, _parent_module_id, opts) do
    assigns = build_assigns(child_module, child_block, vars, refs, opts)
    assigns = Map.put(assigns, :forloop, forloop)

    HeexRenderer.render_to_string(
      "child_#{child_module.id}",
      child_module.code,
      assigns
    )
  end

  @impl true
  def render_container(container, children_html, block, opts) do
    assigns =
      opts[:context]
      |> context_assigns()
      |> Map.merge(%{
        block: block,
        content: children_html,
        render_context: render_context(opts)
      })

    HeexRenderer.render_to_string("container_#{container.id}", container.code, assigns)
  end

  # -- Private --

  defp build_assigns(module, block, processed_vars, processed_refs, opts) do
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

    base =
      context_assigns(opts[:context])
      |> Map.merge(%{
        block: simple_block,
        content: "",
        entries: [],
        entries_with_meta: [],
        forloop: nil,
        refs: processed_refs,
        render_context: render_context(opts),
        parser_module: opts[:parser_module] || Brando.Villain.Parser,
        module_id: block.module_id,
        refs_field: nil,
        target: nil,
        target_ref: nil,
        form_id: nil,
        _heex_ctx: %{
          render_context: render_context(opts),
          refs: processed_refs,
          parser_module: opts[:parser_module] || Brando.Villain.Parser,
          liquex_context: opts[:context]
        }
      })

    # Merge vars at the top level (e.g., @my_var)
    put_vars(base, processed_vars)
  end

  @doc false
  def context_assigns(nil), do: @context_assign_defaults

  def context_assigns(context) do
    Enum.reduce(@context_assign_defaults, @context_assign_defaults, fn {assigns_key, default}, assigns ->
      context_key = Atom.to_string(assigns_key)
      Map.put(assigns, assigns_key, Liquex.Context.get(context, context_key) || default)
    end)
  end

  @doc false
  def put_vars(assigns, processed_vars) do
    Enum.reduce(processed_vars, assigns, fn {k, v}, acc ->
      key = if is_atom(k), do: k, else: String.to_atom(k)
      Map.put(acc, key, v)
    end)
  end

  defp render_context(opts) do
    if Map.get(opts, :brando_render_for_admin), do: :admin, else: :publish
  end

  defp maybe_add_datasource_entries(assigns, module, block) do
    case module do
      %{datasource: true, datasource_type: :list, datasource_module: ds_module, datasource_query: query} ->
        language = assigns[:language]
        request = assigns[:request]

        mapped_vars =
          block.vars
          |> map_vars()
          |> Map.merge(%{"request" => request})

        {:ok, entries} = Brando.Datasource.list_results(ds_module, query, mapped_vars, language)
        Map.put(assigns, :entries, entries || [])

      %{datasource: true, datasource_type: :selection, datasource_module: ds_module, datasource_query: query} ->
        identifier_ids = Enum.map(block.block_identifiers, & &1.identifier_id)
        {:ok, entries} = Brando.Datasource.get_selection(ds_module, query, identifier_ids)
        entries_with_meta = Brando.Villain.Parser.add_meta_to_entries(entries, block)

        assigns
        |> Map.put(:entries, entries || [])
        |> Map.put(:entries_with_meta, entries_with_meta || [])

      _ ->
        Map.put(assigns, :entries, [])
    end
  end

  defp map_vars(nil), do: %{}
  defp map_vars(%Ecto.Association.NotLoaded{}), do: %{}

  defp map_vars(vars) do
    Map.new(vars, fn var -> {var.key, var.value} end)
  end
end
