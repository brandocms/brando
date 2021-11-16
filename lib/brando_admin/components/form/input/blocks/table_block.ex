defmodule BrandoAdmin.Components.Form.Input.Blocks.TableBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Form.Input.RenderVar

  # prop base_form, :any
  # prop data_field, :atom
  # prop block, :any
  # prop block_count, :integer
  # prop index, :any
  # prop is_ref?, :boolean, default: false
  # prop belongs_to, :string

  # prop insert_block, :event, required: true
  # prop duplicate_block, :event, required: true

  # data block_data, :any
  # data uid, :string

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def update(assigns, socket) do
    block_data =
      assigns.block
      |> inputs_for(:data)
      |> List.first()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(assigns.block, :uid))
     |> assign(:block_data, block_data)}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="table-block"
      data-block-index={@index}
      data-block-uid={@uid}>
      <.live_component
        module={Block}
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}
        wide_config>
        <:description></:description>
        <:config>
        </:config>
        <%= hidden_input @block_data, :key %>
        <%= hidden_input @block_data, :instructions %>
        <%= if input_value(@block_data, :instructions) do %>
          <div class="table-instructions">
            <%= input_value(@block_data, :instructions) %>
          </div>
        <% end %>
        <%= if Enum.empty?(v(@block_data, :rows)) do %>
          <div class="empty">
            <figure>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M14 10h-4v4h4v-4zm2 0v4h3v-4h-3zm-2 9v-3h-4v3h4zm2 0h3v-3h-3v3zM14 5h-4v3h4V5zm2 0v3h3V5h-3zm-8 5H5v4h3v-4zm0 9v-3H5v3h3zM8 5H5v3h3V5zM4 3h16a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z"/></svg>
            </figure>
            <div class="instructions">
              <button type="button" class="tiny" phx-click={JS.push("add_row", target: @myself)}><%= gettext "Add row" %></button>
            </div>
          </div>
        <% else %>
          <div
            id={"sortable-#{@uid}-rows"}
            class="table-rows"
            phx-hook="Brando.Sortable"
            data-target={@myself}
            data-sortable-id={"sortable-#{@uid}-rows"}
            data-sortable-handle=".sort-handle"
            data-sortable-selector=".table-row">
            <%= for {row, index} <- Enum.with_index(inputs_for(@block_data, :rows)) do %>
              <div class="table-row draggable" data-id={index}>
                <div class="subform-tools">
                  <button type="button" class="sort-handle">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path class="s" d="M12 2l4.243 4.243-1.415 1.414L12 4.828 9.172 7.657 7.757 6.243 12 2zM2 12l4.243-4.243 1.414 1.415L4.828 12l2.829 2.828-1.414 1.415L2 12zm20 0l-4.243 4.243-1.414-1.415L19.172 12l-2.829-2.828 1.414-1.415L22 12zm-10 2a2 2 0 1 1 0-4 2 2 0 0 1 0 4zm0 8l-4.243-4.243 1.415-1.414L12 19.172l2.828-2.829 1.415 1.414L12 22z" fill="rgba(5,39,82,1)"/></svg>
                  </button>
                  <button
                    phx-click={JS.push("delete_row", target: @myself)}
                    phx-value-index={index}
                    type="button"
                    class="subform-delete"
                    phx-page-loading>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path class="s" d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z" fill="rgba(5,39,82,1)"/></svg>
                  </button>
                </div>

                <Form.poly_inputs form={row} for={:cols} let={%{form: var, index: index}}>
                  <.live_component module={RenderVar} id={"#{row.id}-cols-render-var-#{index}"} var={var} render={:only_important} />
                </Form.poly_inputs>
              </div>
            <% end %>
          </div>
          <button type="button" class="tiny add-row" phx-click={JS.push("add_row", target: @myself)}>{gettext "Add row"}</button>
        <% end %>

        <!-- template row -->
        <%= for tpl_row <- inputs_for(@block_data, :template_row) do %>
          <Form.poly_inputs form={tpl_row} for={:cols} let={%{form: var}}>
            <%= hidden_input var, :key %>
            <%= hidden_input var, :type %>
            <%= hidden_input var, :important %>
            <%= hidden_input var, :label %>
            <%= hidden_input var, :instructions %>
            <%= hidden_input var, :placeholder %>
            <%= hidden_input var, :value %>
          </Form.poly_inputs>
        <% end %>
        <!-- end template -->
      </.live_component>
    </div>
    """
  end

  def handle_event(
        "sequenced",
        %{"ids" => order_indices},
        %{assigns: %{uid: uid, data_field: data_field, base_form: form, block_data: block_data}} =
          socket
      ) do
    changeset = form.source
    rows = input_value(block_data, :rows)

    sorted_rows = Enum.map(order_indices, &Enum.at(rows, &1))

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, uid, %{
        data: %{rows: sorted_rows}
      })

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "add_row",
        _,
        %{assigns: %{uid: uid, data_field: data_field, base_form: form, block_data: block_data}} =
          socket
      ) do
    # replace block
    changeset = form.source
    rows = input_value(block_data, :rows)
    new_row = input_value(block_data, :template_row)

    new_rows = rows ++ [new_row]

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, uid, %{
        data: %{rows: new_rows}
      })

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "delete_row",
        %{"index" => index},
        %{assigns: %{uid: uid, data_field: data_field, base_form: form, block_data: block_data}} =
          socket
      ) do
    # replace block
    changeset = form.source
    rows = input_value(block_data, :rows)

    {_, new_rows} = List.pop_at(rows, String.to_integer(index))

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, uid, %{
        data: %{rows: new_rows}
      })

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
