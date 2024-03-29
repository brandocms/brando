defmodule BrandoAdmin.Components.Form.Input.Blocks.SvgBlock do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  import Brando.Gettext
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks

  # prop block, :form
  # prop base_form, :form
  # prop index, :integer
  # prop block_count, :integer
  # prop is_ref?, :boolean, default: false
  # prop ref_description, :string
  # prop belongs_to, :string
  # prop data_field, :atom

  # prop insert_module, :event, required: true
  # prop duplicate_block, :event, required: true

  # data uid, :string
  # data text_type, :string
  # data initial_props, :map
  # data block_data, :map

  def update(assigns, socket) do
    block = assigns.block
    block_data = Brando.Utils.forms_from_field(block[:data]) |> List.first()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:uid, assigns.block[:uid].value)}
  end

  def render(assigns) do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-index={@index} data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}
      >
        <:description>
          <%= if @ref_description do %>
            <%= @ref_description %>
          <% end %>
        </:description>
        <:config>
          <Input.code
            id={"block-#{@uid}-svg-code"}
            field={@block_data[:code]}
            uid={@uid}
            id_prefix="block_data"
            label={gettext("Code")}
          />
          <Input.text
            field={@block_data[:class]}
            uid={@uid}
            id_prefix="block_data"
            label={gettext("Class")}
          />
        </:config>
        <div
          class="svg-block"
          phx-hook="Brando.SVGDrop"
          id={"block-#{@uid}-svg-drop"}
          data-target={@myself}
        >
          <%= if @block_data[:code].value do %>
            <div class="svg-block-preview" id={"block-#{@uid}-svg-preview"}>
              <%= @block_data[:code].value |> raw %>
            </div>
          <% else %>
            <div class="empty">
              <figure>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M24 12l-5.657 5.657-1.414-1.414L21.172 12l-4.243-4.243 1.414-1.414L24 12zM2.828 12l4.243 4.243-1.414 1.414L0 12l5.657-5.657L7.07 7.757 2.828 12zm6.96 9H7.66l6.552-18h2.128L9.788 21z" />
                </svg>
              </figure>
              <div class="instructions">
                <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}>
                  Configure SVG block
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </Blocks.block>
    </div>
    """
  end

  def handle_event(
        "drop_svg",
        %{"code" => code},
        %{assigns: %{uid: uid, data_field: data_field, base_form: form}} = socket
      ) do
    # replace block
    changeset = form.source

    new_data = %{
      code: code
    }

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, uid, %{data: new_data})

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
