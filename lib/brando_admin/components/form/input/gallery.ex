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
    require Logger
    Logger.error(inspect(gallery, pretty: true))
    assign(socket, :gallery, gallery)
  end

  def render(assigns) do
    ~H"""
    <div>
      <FieldBase.render
        form={@form}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}>
      No gallery!
      </FieldBase.render>
    </div>
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
