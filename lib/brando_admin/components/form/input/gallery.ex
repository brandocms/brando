defmodule BrandoAdmin.Components.Form.Input.Gallery do
  @moduledoc false
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias Brando.Images.GalleryImage
  alias Brando.Utils
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.ImagePicker

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop parent_uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean

  # data gallery, :any
  # data preview_layout, :atom
  # data selected_images, :list

  def update(
        %{new_image: new_image, selected_images: selected_images},
        %{assigns: %{gallery_images: gallery_images}} = socket
      ) do
    {:ok,
     socket
     |> assign(:gallery_images, gallery_images ++ [new_image])
     |> assign(:selected_images, selected_images)}
  end

  def update(
        %{action: :update_image, updated_image: updated_image, force_validation: true},
        %{assigns: %{gallery_images: gallery_images}} = socket
      ) do
    updated_image_id = updated_image.id

    updated_gallery_images =
      Enum.map(gallery_images, fn
        %{image_id: ^updated_image_id} -> %{image_id: updated_image_id, image: updated_image}
        other -> other
      end)

    {:ok, assign(socket, :gallery_images, updated_gallery_images)}
  end

  def update(assigns, socket) do
    schema = assigns.field.form.data.__struct__

    if assigns.parent_uploads[assigns.field.field] == nil do
      raise Brando.Exception.BlueprintError,
        message: """
        Gallery input not found.

        Form input name for gallery was given as `#{assigns.field.field}` — but no such asset was found.
        Ensure that your input name matches your asset name in your blueprint.

        """
    end

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(:preview_layout, assigns.opts[:layout] || :grid)
     |> assign(:schema, schema)
     |> assign_value()}
  end

  defp get_gallery_images(%{gallery_images: nil}), do: []
  defp get_gallery_images(%{gallery_images: []}), do: []
  defp get_gallery_images(%{gallery_images: %Ecto.Association.NotLoaded{}}), do: []
  defp get_gallery_images(%{gallery_images: gallery_images}), do: gallery_images
  defp get_gallery_images(_), do: []

  defp assign_value(%{assigns: %{field: field}} = socket) do
    changeset = field.form.source
    gallery = Ecto.Changeset.get_field(changeset, field.field)
    gallery_images = get_gallery_images(gallery)

    socket
    |> assign(:gallery, gallery)
    |> assign_new(:selected_images, fn -> Enum.map(gallery_images, & &1.image.path) end)
    |> assign_new(:gallery_images, fn -> gallery_images end)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base field={@field} label={@label} instructions={@instructions} class={@class} compact={@compact}>
        <div class="gallery-input">
          <div class="actions">
            <button type="button" class="tiny upload-button">
              {gettext("Upload images")}
              <.live_file_input upload={@parent_uploads[@field.field]} />
            </button>
            <button
              phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}
              type="button"
              class="tiny"
            >
              {gettext("Select images")}
            </button>
          </div>

          <%= for entry <- @parent_uploads[@field.field].entries do %>
            <progress value={entry.progress} max="100">{entry.progress}%</progress>
            <%= for err <- upload_errors(@parent_uploads[@field.field], entry) do %>
              <.alert type={:danger}>
                <:icon>
                  <.icon name="hero-exclamation-triangle" />
                </:icon>
                <:close>
                  <button
                    type="button"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                    phx-value-field_name={@field.field}
                    phx-target={@form_cid}
                    aria-label="cancel"
                  >
                    <.icon name="hero-x-circle" />
                  </button>
                </:close>
                <strong>{Brando.Upload.error_to_string(err)}</strong>
                <br /><br />
                {gettext("Filename")} {entry.client_name}<br />
                {gettext("Filesize")} {Brando.Utils.human_size(entry.client_size)}
              </.alert>
            <% end %>
          <% end %>
          <%= if @gallery_images == [] do %>
            <small>
              {gettext("No associated gallery")}
            </small>
          <% else %>
            <div
              id="sortable-gallery-images"
              phx-hook="Brando.SortableAssocs"
              data-target={@myself}
              data-sortable-id="sortable-gallery"
              data-sortable-handle=".sort-handle"
              data-sortable-selector=".gallery-image"
              class="gallery-images"
            >
              <.inputs_for :let={gallery_form} field={@field}>
                <Input.input type={:hidden} field={gallery_form[:config_target]} />

                <.inputs_for :let={gallery_image} field={gallery_form[:gallery_images]}>
                  <figure class="gallery-image sort-handle draggable" data-id={gallery_image[:image_id].value}>
                    <.gallery_image
                      gallery_images={@gallery_images}
                      gallery_image_field={gallery_image}
                      parent_form_name={gallery_form.name}
                    />
                    <input type="hidden" name={"#{gallery_form.name}[sort_gallery_image_ids][]"} value={gallery_image.index} />
                  </figure>
                  <Input.input type={:hidden} field={gallery_image[:image_id]} />
                  <Input.input type={:hidden} field={gallery_image[:gallery_id]} />
                  <Input.input type={:hidden} field={gallery_image[:creator_id]} />
                </.inputs_for>
              </.inputs_for>
            </div>
          <% end %>
        </div>
      </Form.field_base>
    </div>
    """
  end

  def gallery_image(assigns) do
    gallery_image =
      Enum.find(
        assigns.gallery_images,
        &(to_string(&1.image_id) == to_string(assigns.gallery_image_field[:image_id].value))
      )

    assigns = assign(assigns, :gallery_image, gallery_image)

    ~H"""
    <div :if={@gallery_image}>
      <%= if @gallery_image.image.status == :processed do %>
        <img width="25" height="25" src={"#{Utils.img_url(@gallery_image.image, :thumb, prefix: Utils.media_url())}"} />
        <button
          type="button"
          class="delete-image"
          name={"#{@parent_form_name}[drop_gallery_image_ids][]"}
          value={@gallery_image_field.index}
          phx-click={JS.dispatch("change")}
        >
          <.icon name="hero-x-mark" />
        </button>
      <% else %>
        <div class="img-placeholder">
          <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
            <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
          </svg>
        </div>
      <% end %>
    </div>
    """
  end

  defp sequence(gallery_images) do
    gallery_images
    |> Enum.with_index()
    |> Enum.map(fn {gi, idx} -> Map.put(gi, :sequence, idx) end)
  end

  def handle_event("cancel_upload", %{"ref" => ref, "field_name" => field_name}, socket) do
    {:noreply, cancel_upload(socket, field_name, ref)}
  end

  def handle_event("reposition", _, socket) do
    {:noreply, socket}
  end

  def handle_event("set_target", _, socket) do
    myself = socket.assigns.myself
    selected_images = socket.assigns.selected_images
    schema = socket.assigns.schema
    field = socket.assigns.field
    field_name = field.field

    send_update(ImagePicker,
      id: "image-picker",
      config_target: {"gallery", schema, field_name},
      event_target: myself,
      multi: true,
      selected_images: selected_images
    )

    {:noreply, socket}
  end

  def handle_event(
        "select_image",
        %{"id" => image_id, "selected" => "false"},
        %{assigns: %{field: field, gallery_images: gallery_images, current_user: current_user}} = socket
      ) do
    changeset = field.form.source
    field_name = field.field
    schema = field.form.data.__struct__
    gallery = Ecto.Changeset.get_field(changeset, field_name)

    {:ok, new_image} = Brando.Images.get_image(image_id)

    current_gallery_images =
      if gallery do
        Enum.map(
          gallery.gallery_images || [],
          &Map.take(&1, [:id, :image_id, :gallery_id, :sequence, :creator_id])
        )
      else
        []
      end

    new_gallery_image = %{image_id: String.to_integer(image_id), creator_id: current_user.id}
    new_gallery_images = current_gallery_images ++ List.wrap(new_gallery_image)

    new_gallery =
      if gallery do
        %{
          id: gallery.id,
          config_target: gallery.config_target,
          gallery_images: sequence(new_gallery_images)
        }
      else
        %{
          config_target: "gallery:#{inspect(schema)}:#{field_name}",
          gallery_images: sequence(new_gallery_images)
        }
      end

    new_gallery_images =
      gallery_images ++
        List.wrap(%GalleryImage{
          image_id: new_image.id,
          image: new_image,
          creator_id: current_user.id
        })

    selected_images = Enum.map(new_gallery_images, & &1.image.path)

    send_update(ImagePicker,
      id: "image-picker",
      selected_images: selected_images
    )

    updated_changeset = put_assoc(changeset, field_name, new_gallery)

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, assign(socket, gallery_images: new_gallery_images, selected_images: selected_images)}
  end

  def handle_event(
        "select_image",
        %{"id" => image_id, "selected" => "true"},
        %{assigns: %{field: field, gallery_images: gallery_images}} = socket
      ) do
    changeset = field.form.source
    gallery = Ecto.Changeset.get_field(changeset, field.field)
    field_name = field.field
    image_id = (is_binary(image_id) && String.to_integer(image_id)) || image_id
    new_gallery_images = Enum.filter(gallery_images, &(&1.image_id != image_id))
    selected_images = Enum.map(new_gallery_images, & &1.image.path)

    send_update(ImagePicker,
      id: "image-picker",
      selected_images: selected_images
    )

    slimmed_gallery_images =
      Enum.map(
        new_gallery_images,
        &Map.take(&1, [:id, :image_id, :gallery_id, :sequence, :creator_id])
      )

    new_gallery = %{
      id: gallery.id,
      config_target: gallery.config_target,
      gallery_images: sequence(slimmed_gallery_images)
    }

    updated_changeset = put_assoc(changeset, field_name, new_gallery)

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, assign(socket, gallery_images: new_gallery_images, selected_images: selected_images)}
  end

  # def handle_event(
  #       "sequenced",
  #       %{"ids" => order_indices},
  #       %{
  #         assigns: %{
  #           field: field,
  #           gallery_images: gallery_images
  #         }
  #       } = socket
  #     ) do
  #   field_name = field.field
  #   changeset = field.form.source
  #   module = changeset.data.__struct__
  #   form_id = "#{module.__naming__().singular}_form"

  #   gallery = Ecto.Changeset.get_field(changeset, field_name)

  #   entries =
  #     Enum.map(
  #       gallery.gallery_images,
  #       &Map.take(&1, [:id, :image_id, :gallery_id, :sequence, :creator_id])
  #     )

  #   sorted_entries =
  #     Enum.map(Enum.with_index(order_indices), fn {id, idx} ->
  #       Enum.find(entries, &(to_string(&1.image_id) == to_string(id))) |> Map.put(:sequence, idx)
  #     end)

  #   sorted_gallery_images =
  #     Enum.map(order_indices, fn id -> Enum.find(gallery_images, &(&1.image_id == id)) end)

  #   updated_gallery = %{
  #     id: gallery.id,
  #     config_target: gallery.config_target,
  #     gallery_images: sorted_entries
  #   }

  #   updated_changeset = Ecto.Changeset.put_assoc(changeset, field_name, updated_gallery)

  #   send_update(BrandoAdmin.Components.Form,
  #     id: form_id,
  #     action: :update_changeset,
  #     changeset: updated_changeset
  #   )

  #   {:noreply, assign(socket, :gallery_images, sorted_gallery_images)}
  # end

  def handle_event("edit_image", %{"id" => _id}, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_selected", %{"ids" => ids_json}, socket) do
    rejected_indices =
      ids_json
      |> Jason.decode!()
      |> MapSet.new()

    field_name = socket.assigns.input.name
    changeset = socket.assigns.field.form.source
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
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, assign(socket, :selected_images, [])}
  end
end
