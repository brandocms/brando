defmodule BrandoAdmin.Components.Form.Input.Gallery do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Ecto.Changeset

  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Input.Gallery.ImagePreview

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean

  # data gallery, :any
  # data preview_layout, :atom
  # data selected_images, :list

  def mount(socket) do
    {:ok, assign(socket, :selected_images, [])}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(preview_layout: assigns.opts[:layout] || :grid)
     |> assign_value()}
  end

  defp assign_value(%{assigns: %{form: form, field: field}} = socket) do
    gallery = get_field(form.source, field)
    assign(socket, :gallery, gallery)
  end

  def render(assigns) do
    ~H"""
    <FieldBase.render
      form={@form}
      field={@field}
      label={@label}
      instructions={@instructions}
      class={@class}
      compact={@compact}>

      <div
        id={"#{@form.id}-#{@field}-gallery-dropzone"}
        class="input-gallery">

        <div class="button-group">
          <div class="file-input-wrapper">
            <span class="label">
              Upload
            </span>
            <%= live_file_input Map.get(@uploads, @field) %>
          </div>
          <button
            type="button"
            class="secondary"
            :on-click="delete_selected"
            phx-value-ids={Jason.encode!(@selected_images)}
            disabled={Enum.empty?(@selected_images)}
            phx-page-loading>
            Delete <span><%= Enum.count(@selected_images) %></span> selected
          </button>

          <button
            type="button"
            class="secondary"
            :on-click="reset_gallery"
            phx-page-loading>Reset field</button>
        </div>
        <div
          class="drop-target"
          phx-drop-target={@uploads[@field].ref}>
          <div class="drop-indicator">
            <div>Drop here to upload</div>
          </div>
        </div>

        <%= if !@gallery || Enum.empty?(@gallery) && Enum.empty?(@uploads[@field].entries) do %>
          <div class="gallery-empty">
            No images in image gallery.
          </div>
        <% end %>

        <%= if !Enum.empty?(@uploads[@field].entries) do %>
          <div class="input-gallery-previews">
            <%= for entry <- @uploads[@field].entries do %>
              <%= if entry.progress do %>
                <article class="upload-entry" data-upload-uuid={entry.uuid}>
                  <progress value={entry.progress} max="100"></progress>
                  <div class="file-info">
                    <div class="preview">
                      <%= live_img_preview entry %>
                    </div>

                    <div class="file">
                      <%= entry.client_name %>
                      <small><%= entry.client_type %>, <%= Brando.Utils.human_size(entry.client_size) %></small>
                      <div class="progress-percent">
                        <%= entry.progress %>%
                      </div>
                    </div>
                  </div>

                  <%= for err <- upload_errors(@uploads[@field], entry) do %>
                    <p class="alert alert-danger">
                      <%= Brando.Upload.error_to_string(err) %>
                    </p>
                  <% end %>
                </article>
              <% end %>
            <% end %>
          </div>
        <% end %>

        <%= if !Enum.empty?(@gallery) do %>
          <div
            id={"sortable-#{@form.id}-#{@field}-images"}
            class={render_classes(["image-previews", @preview_layout])}
            phx-hook="Brando.Sortable"
            data-target={@myself}
            data-sortable-id={"sortable-#{@form.id}-#{@field}-images"}
            data-sortable-handle=".sort-handle"
            data-sortable-selector=".image-preview">
            <Form.inputs
              let={%{form: sf, index: idx}}
              form={@form}
              for={@field}>
              <div
                class={render_classes([
                  "image-preview",
                  "sort-handle",
                  "draggable",
                  selected: idx in @selected_images
                ])}
                data-id={idx}
                :on-click="select_row"
                phx-value-id={idx}
                phx-page-loading>
                <%= case @preview_layout do %>
                  <% :grid -> %>
                    <div class="overlay">
                      <button
                        type="button"
                        :on-click="edit_image"
                        phx-value-id={idx}>Edit</button>
                    </div>
                    <ImagePreview.render
                      layout={:grid}
                      form={sf} />
                <% end %>

                <div class="image-meta">
                  <.live_component module={Modal}
                    title="Edit image"
                    center_header={true}
                    id={"edit-image-#{@form.id}-#{@field}-modal-#{idx}"}>
                    <div class="field-wrapper">
                      <div class="label-wrapper">
                        <label class="control-label"><span>Caption/Title</span></label>
                      </div>
                      <div class="field-base">
                        <%= text_input sf, :title, class: "text" %>
                      </div>
                    </div>
                    <div class="field-wrapper">
                      <div class="label-wrapper">
                        <label class="control-label"><span>Alt text (for accessibility)</span></label>
                      </div>
                      <div class="field-base">
                        <%= text_input sf, :alt, class: "text" %>
                      </div>
                    </div>
                    <div class="field-wrapper">
                      <div class="label-wrapper">
                        <label class="control-label"><span>Credits</span></label>
                      </div>
                      <div class="field-base">
                        <%= text_input sf, :credits, class: "text" %>
                      </div>
                    </div>

                    <%= hidden_input sf, :id %>
                    <%= hidden_input sf, :cdn %>
                    <%= hidden_input sf, :dominant_color %>
                    <%= hidden_input sf, :height %>
                    <%= hidden_input sf, :path %>
                    <%= hidden_input sf, :width %>
                    <%= hidden_input sf, :marked_as_deleted %>

                    <Form.inputs
                      form={sf}
                      for={:focal}
                      let={%{form: focal_form}}>
                      <%= hidden_input focal_form, :x %>
                      <%= hidden_input focal_form, :y %>
                    </Form.inputs>

                    <Form.map_inputs
                      let={%{value: value, name: name}}
                      form={sf}
                      for={:sizes}>
                      <input type="hidden" name={"#{name}"} value={"#{value}"} />
                    </Form.map_inputs>
                  </.live_component>
                </div>
              </div>
            </Form.inputs>
          </div>
        <% end %>
      </div>
    </FieldBase.render>
    """
  end

  def handle_event("sequenced", %{"ids" => order_indices}, socket) do
    field_name = socket.assigns.input.name
    changeset = socket.assigns.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    entries = Ecto.Changeset.get_field(changeset, field_name)
    sorted_entries = Enum.map(order_indices, &Enum.at(entries, &1))
    updated_changeset = Ecto.Changeset.put_embed(changeset, field_name, sorted_entries)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("select_row", %{"id" => id}, socket) do
    {:noreply, select_row(socket, String.to_integer(id))}
  end

  def handle_event("edit_image", %{"id" => _id}, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_selected", %{"ids" => ids_json}, socket) do
    rejected_indices =
      ids_json
      |> Jason.decode!()
      |> MapSet.new()

    field_name = socket.assigns.input.name
    changeset = socket.assigns.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    entries = Ecto.Changeset.get_field(changeset, field_name)

    filtered_entries =
      entries
      |> Stream.with_index()
      |> Stream.reject(fn {_item, index} -> index in rejected_indices end)
      |> Enum.map(&elem(&1, 0))

    updated_changeset = Ecto.Changeset.put_embed(changeset, field_name, filtered_entries)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, assign(socket, :selected_images, [])}
  end

  defp select_row(%{assigns: assigns} = socket, id) do
    selected_images = Map.get(assigns, :selected_images, [])

    updated_selected_images =
      if id in selected_images do
        List.delete(selected_images, id)
      else
        [id | selected_images]
      end

    assign(socket, :selected_images, updated_selected_images)
  end
end
