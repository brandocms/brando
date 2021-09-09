defmodule BrandoAdmin.Components.Form.Input.Blocks.Ref do
  use Surface.Component
  use Phoenix.HTML
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Form.Input.Blocks
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  prop module_refs, :list, required: true
  prop module_ref_name, :string, required: true
  prop base_form, :any
  prop uploads, :any
  prop data_field, :atom

  data module_name, :string
  data ref_index, :any
  data ref, :any
  data ref_uid, :string
  data ref_block, :any
  data ref_form, :form
  data block_count, :integer

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_ref()}
  end

  def assign_ref(%{assigns: %{module_refs: refs, module_ref_name: ref}} = socket) do
    case Enum.find(refs, &(elem(&1, 0).data.name == ref)) do
      {ref_form, ref_index} ->
        ref_block = inputs_for_block(ref_form, :data) |> List.first()

        socket
        |> assign(:block_count, Enum.count(refs))
        |> assign(:ref_index, ref_index)
        |> assign(:ref_form, ref_form)
        |> assign(:ref_block, ref_block)
        |> assign(:ref_uid, v(ref_block, :uid))
        |> assign(:ref, ref_form.data)

      nil ->
        require Logger

        Logger.error("""
        ==> Ref not found

        Available refs:
        #{inspect(Enum.map(refs, &elem(&1, 0).data), pretty: true)}

        Ref name:
        #{inspect(ref, pretty: true)}

        --- end ^
        """)

        socket
    end
  end

  def render(assigns) do
    ~F"""
    <section b-ref={@ref.name}>
      <Blocks.DynamicBlock
        id={@ref_uid}
        is_ref?={true}
        data_field={@data_field}
        ref_name={@ref.name}
        ref_description={@ref.description}
        index={@ref_index}
        block_count={@block_count}
        block={@ref_block}
        base_form={@base_form}
        uploads={@uploads} />

      <HiddenInput form={@ref_form} field={:description} />
      <HiddenInput form={@ref_form} field={:name} />
    </section>
    """
  end
end
