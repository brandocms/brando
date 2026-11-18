defmodule Brando.Villain.TemplateAdapter.Heex do
  @moduledoc """
  HEEx template adapter for Villain modules and containers.

  Builds an assigns map (vars at top level + system assigns) and
  delegates to `Brando.Villain.HeexRenderer` for compilation and rendering.

  A template is compiled before its assigns are built: a var's key comes from
  stored content and only becomes an assign if the atom exists, and compiling
  makes the ones the template reads exist. The first render after a restart
  would otherwise lose a key the template reads.
  """

  @behaviour Brando.Villain.TemplateAdapter

  alias Brando.Datasource
  alias Brando.Villain.HeexRenderer
  alias Brando.Villain.RenderFailures
  alias Brando.Villain.TemplateAdapter

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
    render(module.id, module.code, opts, fn ->
      module
      |> build_assigns(block, processed_vars, processed_refs, opts)
      |> maybe_add_datasource_entries(module, block)
    end)
  end

  @impl true
  def render_multi_module(module, block, base_vars, base_refs, children, content, opts) do
    render(module.id, module.code, opts, fn ->
      module
      |> build_assigns(block, base_vars, base_refs, opts)
      |> Map.put(:entries, children)
      |> Map.put(:content, content)
    end)
  end

  @impl true
  def render_child_module(child_module, child_block, vars, refs, forloop, _parent_module_id, opts) do
    render("child_#{child_module.id}", child_module.code, opts, fn ->
      child_module
      |> build_assigns(child_block, vars, refs, opts)
      |> Map.put(:forloop, forloop)
    end)
  end

  @impl true
  def render_container(container, children_html, block, opts) do
    render("container_#{container.id}", container.code, opts, fn ->
      opts[:context]
      |> context_assigns()
      |> Map.merge(%{
        block: block,
        content: children_html,
        render_context: render_context(opts)
      })
    end)
  end

  # Compiled before its assigns are built (see the moduledoc). In a render
  # that collects failures (`Brando.Villain.parse_checked/3`), a template that
  # does not compile or raises is recorded and renders nothing; any other
  # render raises, as the editor has always seen it.
  defp render(id, code, opts, assigns) do
    compiled? =
      RenderFailures.guard(:parse, false, fn ->
        HeexRenderer.get_or_compile!(id, code)
        true
      end)

    if compiled? do
      RenderFailures.guard(:render, "", fn ->
        id |> HeexRenderer.render_to_string(code, assigns.()) |> own_liquid(opts)
      end)
    else
      ""
    end
  end

  # -- Private --

  # Liquid written in the template runs here, not when the output is printed
  # inside another HEEx template, where it is a value and stays text.
  defp own_liquid(html, %{context: %Liquex.Context{} = context}) do
    if String.contains?(html, ["{{", "{%"]), do: Brando.Villain.parse_and_render(html, context), else: html
  end

  defp own_liquid(html, _opts), do: html

  defp build_assigns(module, block, processed_vars, processed_refs, opts) do
    simple_block = TemplateAdapter.simple_block(module, block, row_keys: :existing_atom)

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

  @doc """
  The site-wide assigns a HEEx module template reads (globals, identity, entry,
  language and so on), taken from the Liquex render context with defaults for
  anything missing.
  """
  def context_assigns(nil), do: @context_assign_defaults

  def context_assigns(context) do
    Enum.reduce(@context_assign_defaults, @context_assign_defaults, fn {assigns_key, default}, assigns ->
      context_key = Atom.to_string(assigns_key)
      Map.put(assigns, assigns_key, Brando.Villain.raw_context(context, context_key) || default)
    end)
  end

  @doc """
  Merges processed block vars into `assigns` as top-level atom keys, so templates
  read `@my_var`. A key that exists as no atom is left out: call this after the
  template is compiled, so the keys it reads exist.
  """
  def put_vars(assigns, processed_vars) do
    Enum.reduce(processed_vars, assigns, fn {k, v}, acc ->
      case Brando.Utils.existing_atom(k) do
        {:ok, key} -> Map.put(acc, key, v)
        :error -> acc
      end
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

        {:ok, entries} = Datasource.list_results(ds_module, query, mapped_vars, language, :list)
        Map.put(assigns, :entries, entries || [])

      %{datasource: true, datasource_type: :selection, datasource_module: ds_module, datasource_query: query} ->
        identifier_ids = Enum.map(block.block_identifiers, & &1.identifier_id)
        {:ok, entries} = Datasource.get_selection(ds_module, query, identifier_ids)
        entries_with_meta = Brando.Villain.Parser.add_meta_to_entries(entries, block)

        assigns
        |> Map.put(:entries, entries || [])
        |> Map.put(:entries_with_meta, entries_with_meta || [])

      # The one entry chosen for a `:single` block, as `entries`.
      %{datasource: true, datasource_type: :single, datasource_module: ds_module, datasource_query: query} ->
        ids = block.block_identifiers |> Enum.sort_by(&(&1.sequence || 0)) |> Enum.map(& &1.identifier_id)
        {:ok, entries} = Datasource.get_single_entries(ds_module, query, ids)
        Map.put(assigns, :entries, entries)

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
