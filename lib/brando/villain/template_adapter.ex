defmodule Brando.Villain.TemplateAdapter do
  @moduledoc """
  Behaviour for template adapters used by the Villain parser.

  Template adapters handle the rendering of module and container code
  for different template engines (Liquex, HEEx).
  """

  @type module_def :: map()
  @type container_def :: map()
  @type block :: map()
  @type opts :: map()
  @type vars :: map()
  @type refs :: map()
  @type children :: list()

  @doc """
  Render a single module block.

  Receives the module definition, block data, processed vars and refs, and parser opts.
  Returns rendered HTML string.
  """
  @callback render_module(module_def, block, vars, refs, opts) :: String.t()

  @doc """
  Render a multi module block (parent with children).

  Receives the module definition, block data, processed vars and refs,
  children entries, rendered children HTML content, and parser opts.
  Returns rendered HTML string.
  """
  @callback render_multi_module(module_def, block, vars, refs, children, String.t(), opts) :: String.t()

  @doc """
  Render a single child block within a multi module.

  Receives the child module definition, child block, processed vars and refs,
  forloop data, parent module id, and parser opts.
  Returns rendered HTML string.
  """
  @callback render_child_module(module_def, block, vars, refs, map(), integer(), opts) :: String.t()

  @doc """
  Render a container block.

  Receives the container definition, rendered children HTML, block data, and parser opts.
  Returns rendered HTML string.
  """
  @callback render_container(container_def, String.t(), block, opts) :: String.t()

  @doc """
  The `block` a module template sees: the block's own fields plus the module's class.

  Each table row also carries its vars by key, so `{{ row.city }}` (or `row.city`
  in HEEx) reads the row's `city` var. Row fields win over a var of the same
  name, so positional access through `row.vars[0].value` keeps working.
  """
  def simple_block(module, block) do
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
    |> Map.replace_lazy(:table_rows, &table_rows/1)
    |> Map.put(:class, module.class)
  end

  defp table_rows(rows) when is_list(rows), do: Enum.map(rows, &table_row/1)
  defp table_rows(rows), do: rows

  defp table_row(%{vars: vars} = row) do
    vars
    |> Brando.Villain.Parser.process_vars()
    |> Map.new(fn {key, value} -> {to_atom(key), value} end)
    |> Map.merge(if is_struct(row), do: Map.from_struct(row), else: row)
  end

  defp table_row(row), do: row

  defp to_atom(key) when is_atom(key), do: key
  defp to_atom(key), do: String.to_atom(key)
end
