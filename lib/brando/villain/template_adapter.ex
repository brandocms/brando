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
end
