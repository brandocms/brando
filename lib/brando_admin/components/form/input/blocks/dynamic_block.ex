defmodule BrandoAdmin.Components.Form.Input.Blocks.DynamicBlock do
  use BrandoAdmin, :component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.Input.Blocks

  # prop block, :any
  # prop base_form, :any
  # prop index, :any
  # prop block_count, :integer
  # prop is_ref?, :boolean, default: false
  # prop ref_name, :string
  # prop ref_description, :string
  # prop id, :any
  # prop uploads, :any
  # prop data_field, :atom
  # prop belongs_to, :string

  # prop insert_block, :event
  # prop duplicate_block, :event

  # data block_id, :module
  # data block_module, :module
  # data random_id, :string

  def v(form, field), do: input_value(form, field)

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:insert_block, fn -> nil end)
      |> assign_new(:duplicate_block, fn -> nil end)
      |> assign_new(:belongs_to, fn -> nil end)
      |> assign_new(:is_ref?, fn -> false end)
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:ref_name, fn -> nil end)
      |> assign_new(:ref_description, fn -> nil end)
      |> assign_new(:block_id, fn -> v(assigns.block, :uid) end)
      |> assign_new(:block_module, fn ->
        block_type = (v(assigns.block, :type) |> to_string |> Recase.to_pascal()) <> "Block"
        Module.concat([Blocks, block_type])
      end)

    assigns =
      if is_nil(input_value(assigns.block, :uid)) do
        random_id = Brando.Utils.random_string(13) |> String.upcase()

        block =
          put_in(
            assigns.block,
            [Access.key(:source), Access.key(:data), Access.key(:uid)],
            random_id
          )

        assigns
        |> assign(:random_id, random_id)
        |> assign(:block, block)
      else
        assigns
      end

    ~H"""
    <.live_component
      module={@block_module}
      id={@block_id || @random_id}
      block={@block}
      is_ref?={@is_ref?}
      base_form={@base_form}
      data_field={@data_field}
      index={@index}
      opts={@opts}
      belongs_to={@belongs_to}
      ref_name={@ref_name}
      ref_description={@ref_description}
      block_count={@block_count}
      insert_block={@insert_block}
      duplicate_block={@duplicate_block}
      uploads={@uploads} />
    """
  end
end
