defmodule BrandoAdmin.Components.Form.Input.Image do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input

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

  # data show_edit_meta, :boolean, default: false
  # data focal, :any
  # data image, :any
  # data file_name, :any
  # data relation_field, :atom

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:focal, fn -> {nil, nil} end)
     |> assign_new(:opts, fn -> [] end)
     |> assign_new(:previous_image_id, fn -> nil end)
     |> assign_new(:label, fn -> nil end)
     |> assign_new(:instructions, fn -> nil end)
     |> assign_new(:path, fn -> [] end)
     |> assign_new(:image, fn -> nil end)
     |> assign_new(:image_id, fn -> nil end)
     |> assign_new(:parent_form, fn -> nil end)
     |> assign_new(:small, fn -> false end)
     |> assign_new(:square, fn -> false end)
     |> assign_new(:placeholder, fn -> nil end)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:form_id, fn ->
        form = assigns.field.form
        path = Brando.Utils.get_path_from_field_name(form.name)
        module_from_form = form.source.data.__struct__

        module =
          if path == [] do
            module_from_form
          else
            Brando.Utils.get_parent_module_from_field_name(form.name, module_from_form)
          end

        "#{module.__naming__().singular}_form"
      end)

    changeset = assigns.field.form.source
    relation_field_atom = String.to_existing_atom("#{assigns.field.field}_id")
    relation_field = assigns.field.form[relation_field_atom]
    image_id = changeset |> get_field(relation_field_atom) |> try_force_int()
    image_from_changeset = get_field(changeset, assigns.field.field)
    full_path_fk = socket.assigns.path ++ [relation_field_atom]

    {socket, image} = resolve_image(socket, image_id, image_from_changeset, full_path_fk)

    file_name = if is_map(image) && image.path, do: Path.basename(image.path)

    {:ok,
     socket
     |> prepare_input_component()
     |> assign(:file_name, file_name)
     |> assign_new(:editable, fn -> Keyword.get(socket.assigns.opts, :editable, true) end)
     |> assign_new(:relation_field, fn -> relation_field end)}
  end

  # Resolves which image to display by comparing the changeset FK, the cached
  # image in assigns, and the image association from the changeset. Returns
  # {updated_socket, image_or_nil}.
  defp resolve_image(socket, image_id, image_from_changeset, full_path_fk) do
    %{image: image, image_id: prev_image_id, focal: focal} = socket.assigns

    cond do
      # Nested form edge case: image struct has no ID and FK is nil.
      # Try resolving via the nested changeset path.
      not is_nil(image) and is_nil(image.id) and is_nil(image_id) ->
        fetch_image_by_path(socket, full_path_fk)

      # FK cleared — discard the currently loaded image
      is_nil(image_id) and not is_nil(image) ->
        {socket |> assign(:focal, {nil, nil}) |> assign(:image_id, nil) |> assign(:image, nil), nil}

      # Image not loaded yet, or FK now points to a different image — fetch from DB
      image_id_needs_fetch?(image, image_id) ->
        fetch_image(socket, image_id)

      # Cached image's focal diverged from tracked focal — refetch latest from DB
      not is_nil(image) and focal != {nil, nil} and focal != {image.focal.x, image.focal.y} ->
        fetch_image(socket, image_id)

      # Changeset carries a fresher version of the image's display attributes
      not is_nil(image) and not is_nil(image_from_changeset) and
          image_display_changed?(image, image_from_changeset, focal) ->
        {socket
         |> assign(:image, image_from_changeset)
         |> assign(:focal, {image_from_changeset.focal.x, image_from_changeset.focal.y}), image_from_changeset}

      # FK value updated but no fetch needed (image already matches)
      image_id != prev_image_id ->
        {assign(socket, :image_id, image_id), image}

      # Image still processing — poll DB for updated status
      not is_nil(image) and image.status == :unprocessed ->
        fetch_image(socket, image_id)

      true ->
        {socket, image}
    end
  end

  defp image_id_needs_fetch?(nil, image_id), do: not is_nil(image_id)

  defp image_id_needs_fetch?(image, image_id),
    do: not is_nil(image_id) and to_string(image.id) != to_string(image_id)

  defp image_display_changed?(image, from_changeset, focal) do
    (focal != {nil, nil} and {from_changeset.focal.x, from_changeset.focal.y} != focal) or
      image.title != from_changeset.title or
      image.credits != from_changeset.credits or
      image.alt != from_changeset.alt or
      (image.id == from_changeset.id and
         (image.width != from_changeset.width or
            image.height != from_changeset.height or
            image.status != from_changeset.status))
  end

  defp fetch_image(socket, image_id) do
    case Brando.Images.get_image(image_id) do
      {:ok, image} ->
        {socket
         |> assign(:image, image)
         |> assign(:image_id, image_id)
         |> assign(:focal, {image.focal.x, image.focal.y}), image}

      {:error, _} ->
        {socket, nil}
    end
  end

  defp fetch_image_by_path(socket, full_path_fk) do
    changeset = socket.assigns.field.form.source

    image_id =
      changeset
      |> EctoNestedChangeset.get_at(full_path_fk)
      |> try_force_int()

    case Brando.Images.get_image(image_id) do
      {:ok, image} ->
        {socket |> assign(:image, image) |> assign(:image_id, image_id), image}

      {:error, _} ->
        {socket, nil}
    end
  end

  def try_force_int(str) when is_binary(str), do: String.to_integer(str)
  def try_force_int(int) when is_integer(int), do: int
  def try_force_int(val), do: val

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base
        :if={@editable}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        compact={@compact}
        relation
      >
        <div>
          <div class={["input-image", @small && "small", @square && "square", @compact && "compact"]}>
            <.image_preview
              image={@image}
              field={@field}
              relation_field={@relation_field}
              click={@editable && open_image(@myself)}
              editable={@editable}
              file_name={@file_name}
              compact={@compact}
            />
          </div>
        </div>
      </Form.field_base>
      <%!-- `click={false}`: this branch only renders when `@editable` is false,
            so the old `@editable && open_image(...)` could never be anything
            else. --%>
      <div :if={!@editable} class={["input-image", @small && "small", @square && "square", @compact && "compact"]}>
        <.image_preview
          image={@image}
          field={@field}
          relation_field={@relation_field}
          click={false}
          editable={@editable}
          file_name={@file_name}
          compact={@compact}
        />
      </div>
    </div>
    """
  end

  def open_image(js \\ %JS{}, target) do
    js
    |> JS.push("open_image", target: target)
    |> toggle_drawer("#image-drawer")
  end

  def handle_event("open_image", _, socket) do
    field = socket.assigns.field
    field_name = field.field
    form = field.form
    entry_id = form.data.id
    relation_field = socket.assigns.relation_field
    image_id = socket.assigns.image_id

    # Reload the image from DB to ensure we have the latest
    # caption/credits/alt (the changeset data may be stale)
    image =
      if image_id do
        case Brando.Images.get_image(image_id) do
          {:ok, fresh_image} -> fresh_image
          _ -> socket.assigns.image
        end
      else
        socket.assigns.image
      end

    myself = socket.assigns.myself
    current_user = socket.assigns.current_user

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:active_field:#{entry_id}",
      {:active_field, field.name, current_user.id}
    )

    path = Brando.Utils.get_path_from_field_name(form.name)
    module_from_form = form.source.data.__struct__

    module =
      if path == [] do
        module_from_form
      else
        Brando.Utils.get_parent_module_from_field_name(form.name, module_from_form)
      end

    form_id = "#{module.__naming__().singular}_form"

    # No per-field LiveView upload anymore — uploads go through the sticky
    # UploadManager; the picker is browse/select only.
    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: {"image", form.data.__struct__, field_name},
      event_target: myself,
      multi: false,
      selected_images: if(image_id, do: [image_id], else: []),
      form_id: form_id
    )

    edit_image = %{
      id: image_id,
      path: path,
      field: field_name,
      relation_field: relation_field,
      schema: form.data.__struct__,
      form_id: form_id,
      image: image
    }

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_edit_image,
      edit_image: edit_image
    )

    {:noreply,
     socket
     |> assign(:path, path)
     |> assign(:form_id, form_id)}
  end

  def handle_event("select_image", %{"id" => selected_image_id}, %{assigns: %{form_id: form_id}} = socket) do
    on_change = socket.assigns.on_change
    {:ok, image} = Brando.Images.get_image(selected_image_id)

    # The picker stays mounted while its drawer is hidden. Keep its selection
    # aligned with the image currently shown in the (still unsaved) field
    # drawer, rather than leaving the originally persisted image marked.
    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      selected_images: [image.id]
    )

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_edit_image,
      image: image
    )

    if on_change do
      path = socket.assigns.path
      field_name = socket.assigns.field.field
      field_path = path ++ [field_name]

      on_change.(%{
        event: "update_entry_relation",
        path: field_path,
        updated_relation: image
      })
    end

    {:noreply, socket}
  end

  @doc """
  Show preview if we have an image with a path
  """
  def image_preview(assigns) do
    type_from_path =
      if assigns.image do
        Brando.Images.Utils.image_type(assigns.image.path)
      end

    assigns =
      assigns
      |> assign(:type, type_from_path)
      |> assign_new(:size, fn -> nil end)
      |> assign_new(:value, fn -> nil end)
      |> assign_new(:editable, fn -> true end)
      |> assign_new(:publish, fn -> false end)
      |> assign_new(:compact, fn -> false end)
      |> assign_new(:image_id, fn ->
        if assigns[:image] do
          assigns[:image].id
        end
      end)

    ~H"""
    <div class="asset-field asset-field--single image-wrapper-compact">
      <Input.input :if={@editable} type={:hidden} field={@relation_field} value={@value || @image_id} publish={@publish} />
      <%= if @image do %>
        <%= if @image.status == :processed do %>
          <Content.image image={@image} size={(@size && @size) || (@editable && :thumb) || :smallest} />
        <% else %>
          <div class="img-placeholder">
            <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
              <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
            </svg>
          </div>
        <% end %>
        <div :if={@editable} class="image-info">
          <div :if={!@compact} class="info-wrapper">
            <div class="filename">{@file_name}</div>
            <div class="dims">{@image.width}&times;{@image.height}</div>
            <div :if={@image.title} class="title">● {@image.title}</div>
          </div>
          <button class="tiny" type="button" phx-click={@click}>
            {gettext("Edit image")}
          </button>
        </div>
      <% else %>
        <div class="img-placeholder">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
            <path fill="none" d="M0 0h24v24H0z" /><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z" />
          </svg>
        </div>

        <div :if={@editable} class="image-info">
          <span :if={!@compact}>{gettext("No image associated with field")}</span>
          <button class="tiny" type="button" phx-click={@click} phx-value-id={"edit-image-#{@field.id}"}>
            {gettext("Add image")}
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
