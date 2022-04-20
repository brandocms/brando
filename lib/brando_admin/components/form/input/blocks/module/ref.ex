defmodule BrandoAdmin.Components.Form.Input.Blocks.Module.Ref do
  use BrandoAdmin, :component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  import BrandoAdmin.Components.Form.Input.Blocks.Utils
  import Ecto.Changeset

  # prop module_refs, :list, required: true
  # prop module_ref_name, :string, required: true
  # prop base_form, :any
  # prop uploads, :any
  # prop data_field, :atom

  # data module_name, :string
  # data ref_index, :any
  # data ref, :any
  # data ref_uid, :string
  # data ref_name, :string
  # data ref_block, :any
  # data ref_form, :form
  # data block_count, :integer

  def v(form, field), do: input_value(form, field)

  def assign_ref(%{module_refs: refs, module_ref_name: ref} = assigns) do
    # TODO: assign_new this stuff? do we need to process them every time?
    case Enum.find(refs, &(elem(&1, 0).data.name == ref)) do
      {ref_form, ref_index} ->
        ref_block = inputs_for_block(ref_form, :data) |> List.first()

        assigns =
          assigns
          |> assign(:block_count, Enum.count(refs))
          |> assign(:ref_index, ref_index)
          |> assign(:ref_form, ref_form)
          |> assign(:ref_block, ref_block)
          |> assign(:ref, ref_form.data)
          |> assign(:ref_name, ref)

        assign(
          assigns,
          :ref_uid,
          get_field(ref_block.source, :uid) || Brando.Utils.generate_uid()
        )

      nil ->
        assigns
        |> assign(:block_count, Enum.count(refs))
        |> assign(:ref_index, 0)
        |> assign(:ref_form, nil)
        |> assign(:ref_block, nil)
        |> assign(:ref_uid, nil)
        |> assign(:ref, nil)
        |> assign(:ref_name, ref)
    end
  end

  def render(assigns) do
    assigns = assign_ref(assigns)

    ~H"""
    <%= if @ref do %>
      <section b-ref={@ref.name}>
        <Blocks.dynamic_block
          id={@ref_uid}
          block_id={@ref_uid}
          is_ref?={true}
          data_field={@data_field}
          ref_name={@ref.name}
          ref_description={@ref.description}
          index={@ref_index}
          block_count={@block_count}
          block={@ref_block}
          base_form={@base_form}
          uploads={@uploads} />
        <Input.input type={:hidden} form={@ref_form} field={:description} uid={@ref_uid} id_prefix="ref" />
        <Input.input type={:hidden} form={@ref_form} field={:name} uid={@ref_uid} id_prefix="ref" />
      </section>
    <% else %>
      <section class="alert danger">
        Ref <code><%= @ref_name %></code> is missing!<br><br>
        If the module has been changed, this block might be out of sync!<br><br>
        Available refs are:<br><br>
        <%= for {%{data: %{name: ref_name}}, _} <- @module_refs do %>
          &rarr; <%= ref_name %><br>
        <% end %>
      </section>
    <% end %>
    """
  end
end
