defmodule BrandoAdmin.Components.Form.Subform do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Subform

  import Brando.Gettext

  # prop subform, :any
  # prop form, :any
  # prop blueprint, :any
  # prop uploads, :any
  # prop current_user, :map
  # prop label, :string
  # prop instructions, :string
  # prop placeholder, :string

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> prepare_subform_component()
      |> assign_new(:open_entries, fn -> [] end)
      |> assign(
        :indexed_sub_form_fields,
        Enum.with_index(inputs_for(assigns.form, assigns.subform.field))
      )
      |> assign(:path, List.wrap(assigns.subform.field))

    {:ok, socket}
  end

  def render(%{subform: %{style: {:transformer, transform_field}}} = assigns) do
    upload_key = :"#{assigns.subform.field}|#{transform_field}"
    _ = :"#{assigns.subform.field}|#{transform_field}_id"
    upload_field = Map.get(assigns.uploads, upload_key)
    assigns = assign(assigns, :upload_field, upload_field)

    ~H"""
    <fieldset>
      <Form.field_base
        :if={@subform.cardinality == :many}
        form={@form}
        field={@subform.field}
        label={@label}
        instructions={@instructions}
        class={"subform"}>
        <div
          id={"#{@form.id}-#{@subform.field}-sortable"}
          phx-hook="Brando.SubFormSortable">
          <%= if Enum.empty?(inputs_for(@form, @subform.field)) do %>
            <input type="hidden" name={"#{@form.name}[#{@subform.field}]"} value="" />
            <div class="subform-empty">&rarr; <%= gettext "No associated entries" %></div>
          <% end %>
          <div
            :for={{sub_form, index} <- @indexed_sub_form_fields}
            class={render_classes(["subform-entry", "group", listing: index not in @open_entries])}
            data-id={index}>
            <div class="subform-tools">
              <button
                phx-click={JS.push("edit_subentry", value: %{index: index}, target: @myself)}
                class="subform-edit"
                type="button"
                phx-page-loading>
                <svg :if={index not in @open_entries} xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" width="16" height="16" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
                </svg>
                <svg :if={index in @open_entries} xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" width="16" height="16" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </button>
              <button type="button" class="subform-handle">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" width="16" height="16" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M3 7.5L7.5 3m0 0L12 7.5M7.5 3v13.5m13.5 0L16.5 21m0 0L12 16.5m4.5 4.5V7.5" />
                </svg>
              </button>
              <button
                phx-click={JS.push("remove_subentry", target: @myself)}
                phx-value-index={index}
                type="button"
                class="subform-delete"
                phx-page-loading>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" width="16" height="16">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                </svg>
              </button>
            </div>
            <.listing subform={sub_form} subform_config={@subform} />
            <div class="subform-fields">
              <Subform.Field.render
                :for={input <- @subform.sub_fields}
                cardinality={:many}
                form={@form}
                sub_form={sub_form}
                input={input}
                path={@path ++ [index]}
                uploads={@uploads}
                current_user={@current_user} />
            </div>
          </div>
        </div>
        <div class="actions">
          <button
            id={"#{@form.id}-#{@subform.field}-add-entry"}
            type="button"
            class="add-entry-button"
            phx-click={JS.push("add_subentry", target: @myself)}
            phx-page-loading>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z" fill="rgba(252,245,243,1)"/></svg>
            <%= gettext("Add entry") %>
          </button>
          <label class="upload-button">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            <%= gettext("Pick files") %>
            <.live_file_input upload={@upload_field} />
          </label>
        </div>
      </Form.field_base>
    </fieldset>
    """
  end

  def render(assigns) do
    ~H"""
    <fieldset>
      <Form.field_base
        :if={@subform.cardinality == :one}
        form={@form}
        field={@subform.field}
        label={@label}
        instructions={@instructions}
        class={"subform"}>
        <div
          :for={sub_form <- inputs_for(@form, @subform.field)}
          class="subform-entry">
          <Subform.Field.render
            :for={input <- @subform.sub_fields}
            cardinality={:one}
            form={@form}
            sub_form={sub_form}
            label={@label}
            instructions={@instructions}
            placeholder={@placeholder}
            input={input}
            path={@path}
            uploads={@uploads}
            current_user={@current_user} />
        </div>
      </Form.field_base>
      <Form.field_base
        :if={@subform.cardinality == :many}
        form={@form}
        field={@subform.field}
        label={@label}
        instructions={@instructions}
        class={"subform"}>
        <div
          id={"#{@form.id}-#{@subform.field}-sortable"}
          phx-hook="Brando.SubFormSortable">
          <%= if Enum.empty?(inputs_for(@form, @subform.field)) do %>
            <input type="hidden" name={"#{@form.name}[#{@subform.field}]"} value="" />
            <div class="subform-empty">&rarr; <%= gettext "No associated entries" %></div>
          <% end %>
          <div
            :for={{sub_form, index} <- @indexed_sub_form_fields}
            class={render_classes(["subform-entry", inline: @subform.style == :inline])}
            data-id={index}>
            <div class="subform-tools">
              <button type="button" class="subform-handle">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path class="s" d="M12 2l4.243 4.243-1.415 1.414L12 4.828 9.172 7.657 7.757 6.243 12 2zM2 12l4.243-4.243 1.414 1.415L4.828 12l2.829 2.828-1.414 1.415L2 12zm20 0l-4.243 4.243-1.414-1.415L19.172 12l-2.829-2.828 1.414-1.415L22 12zm-10 2a2 2 0 1 1 0-4 2 2 0 0 1 0 4zm0 8l-4.243-4.243 1.415-1.414L12 19.172l2.828-2.829 1.415 1.414L12 22z" fill="rgba(5,39,82,1)"/></svg>
              </button>
              <button
                phx-click={JS.push("remove_subentry", target: @myself)}
                phx-value-index={index}
                type="button"
                class="subform-delete"
                phx-page-loading>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path class="s" d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z" fill="rgba(5,39,82,1)"/></svg>
              </button>
            </div>

            <Subform.Field.render
              :for={input <- @subform.sub_fields}
              cardinality={:many}
              form={@form}
              sub_form={sub_form}
              input={input}
              path={@path ++ [index]}
              uploads={@uploads}
              current_user={@current_user} />
          </div>
        </div>
        <button
          id={"#{@form.id}-#{@subform.field}-add-entry"}
          type="button"
          class="add-entry-button"
          phx-click={JS.push("add_subentry", target: @myself)}
          phx-page-loading>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z" fill="rgba(252,245,243,1)"/></svg>
          <%= gettext("Add entry") %>
        </button>
      </Form.field_base>
    </fieldset>
    """
  end

  def listing(assigns) do
    {:transformer, image_field} = assigns.subform_config.style

    assigns =
      assigns
      |> assign(:image_field, image_field)
      |> assign(:entry, Ecto.Changeset.apply_changes(assigns.subform.source))

    ~H"""
    <div class="subform-listing">
      <.live_component module={Input.Image}
        id={"#{@subform.id}-image_field"}
        field={@image_field}
        uploads={[]}
        form={@subform}
        label={:hidden}
        square
        editable={false} />
      <div class="subform-listing-row">
        <%= Phoenix.LiveView.HTMLEngine.component(
          @subform_config.listing,
          [entry: @entry],
          {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
        ) %>
      </div>
    </div>
    """
  end

  def handle_event("edit_subentry", %{"index" => index}, socket) do
    open_entries = socket.assigns.open_entries

    if index in open_entries do
      {:noreply, assign(socket, :open_entries, Enum.reject(open_entries, &(&1 == index)))}
    else
      {:noreply, update(socket, :open_entries, &(&1 ++ [index]))}
    end
  end

  def handle_event("add_subentry", _, socket) do
    changeset = socket.assigns.form.source

    default =
      case socket.assigns.subform.default do
        fun when is_function(fun) -> fun.(nil)
        struct -> struct
      end

    field_name = socket.assigns.subform.field

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_field =
      changeset
      |> Ecto.Changeset.get_field(field_name)
      |> Kernel.++([default])

    count = Enum.count(updated_field)

    updated_changeset =
      case Enum.find(socket.assigns.relations, &(&1.name == field_name)) do
        %{type: :has_many} ->
          # assoc
          Ecto.Changeset.put_assoc(changeset, field_name, updated_field)

        _ ->
          # embed
          Ecto.Changeset.put_embed(changeset, field_name, updated_field)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, update(socket, :open_entries, &(&1 ++ [count]))}
  end

  def handle_event("remove_subentry", %{"index" => index}, socket) do
    field_name = socket.assigns.subform.field
    changeset = socket.assigns.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_entries =
      changeset
      |> Ecto.Changeset.get_field(field_name, [])
      |> List.delete_at(String.to_integer(index))

    updated_changeset =
      case Enum.empty?(updated_entries) do
        true ->
          put_in(changeset, [Access.key(:changes), Access.key(field_name)], [])

        false ->
          case Enum.find(socket.assigns.relations, &(&1.name == field_name)) do
            %{type: :has_many} ->
              # assoc
              Ecto.Changeset.put_assoc(changeset, field_name, updated_entries)

            _ ->
              # embed
              Ecto.Changeset.put_embed(changeset, field_name, updated_entries)
          end
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end

  def handle_event("force_validate", _, socket) do
    field_name = socket.assigns.subform.field
    event_id = "#{socket.assigns.form.id}-#{field_name}-add-entry"
    {:noreply, push_event(socket, "b:validate:#{event_id}", %{})}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices}, socket) do
    field_name = socket.assigns.subform.field
    changeset = socket.assigns.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    entries = Ecto.Changeset.get_field(changeset, field_name)
    sorted_entries = Enum.map(order_indices, &Enum.at(entries, &1))

    updated_changeset =
      case Enum.find(socket.assigns.relations, &(&1.name == field_name)) do
        %{type: :has_many} ->
          # assoc
          Ecto.Changeset.put_assoc(changeset, field_name, sorted_entries)

        _ ->
          # embed
          Ecto.Changeset.put_embed(changeset, field_name, sorted_entries)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end
end
