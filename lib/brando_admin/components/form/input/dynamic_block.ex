defmodule BrandoAdmin.Components.Form.Input.Blocks.DynamicBlock do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.Input.Blocks

  prop block, :any
  prop base_form, :any
  prop index, :any
  prop block_count, :integer
  prop is_ref?, :boolean, default: false
  prop ref_name, :string
  prop ref_description, :string
  prop id, :any
  prop uploads, :any
  prop data_field, :atom
  prop belongs_to, :string

  prop insert_block, :event
  prop duplicate_block, :event

  data block_id, :module
  data block_module, :module
  data random_id, :string

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:block_id, fn -> v(assigns.block, :uid) end)
      |> assign_new(:block_module, fn ->
        block_type = (v(assigns.block, :type) |> to_string |> Inflex.camelize()) <> "Block"
        Module.concat([Blocks, block_type])
      end)

    socket =
      if is_nil(input_value(assigns.block, :uid)) do
        random_id = Brando.Utils.random_string(13) |> String.upcase()

        block =
          put_in(
            assigns.block,
            [Access.key(:source), Access.key(:data), Access.key(:uid)],
            random_id
          )

        socket
        |> assign(:random_id, random_id)
        |> assign(:block, block)
      else
        socket
      end

    {:ok, socket}
  end

  def render(assigns) do
    ~F"""
    {live_component(@socket, @block_module,
      id: @block_id || @random_id,
      block: @block,
      is_ref?: @is_ref?,
      base_form: @base_form,
      data_field: @data_field,
      index: @index,
      belongs_to: @belongs_to,
      ref_name: @ref_name,
      ref_description: @ref_description,
      block_count: @block_count,
      insert_block: @insert_block,
      duplicate_block: @duplicate_block,
      uploads: @uploads
    )}
    """
  end
end
