defmodule BrandoAdmin.Components.Form.Input.Blocks.HeaderBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block

  # prop block, :any
  # prop base_form, :any
  # prop index, :any
  # prop block_count, :integer
  # prop is_ref?, :boolean, default: false
  # prop belongs_to, :string

  # prop insert_block, :event, required: true
  # prop duplicate_block, :event, required: true

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:level, v(assigns.block, :level))
     |> assign(:uid, v(assigns.block, :uid))
     |> assign(:block_data, inputs_for(assigns.block, :data))}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      data-block-index={@index}
      data-block-uid={@uid}>
      <.live_component module={Block}
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>(H<%= @level %>)</:description>
        <:config>
          <Input.radios
            form={@block_data}
            field={:level}
            label="Level"
            opts={[options: [
              %{label: "H1", value: 1},
              %{label: "H2", value: 2},
              %{label: "H3", value: 3},
              %{label: "H4", value: 4},
              %{label: "H5", value: 5},
              %{label: "H6", value: 6},
            ]]} />

          <Input.text
            form={@block_data}
            field={:id}
            label="ID" />

          <Input.text
            form={@block_data}
            field={:link}
            label="Link" />
        </:config>
        <div class="header-block">
          <Input.textarea
            form={@block_data}
            field={:text}
            id={"block-#{@uid}-textarea"}
            class={"h#{@level}"}
            data_autosize={true}
            phx_debounce={750}
            phx_update={"ignore"}
            rows={1} />
          <Input.input type={:hidden} form={@block_data} field={:class} />
          <Input.input type={:hidden} form={@block_data} field={:placeholder} />
        </div>
      </.live_component>
    </div>
    """
  end
end
