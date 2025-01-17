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
  # data upload_field, :any
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
    # TODO: do we have a form_cid we can use instead of this form id stuff?

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

    relation_field_atom = String.to_existing_atom("#{assigns.field.field}_id")
    relation_field = assigns.field.form[relation_field_atom]
    changeset = assigns.field.form.source

    full_path_fk = socket.assigns.path ++ [relation_field_atom]

    image_id =
      changeset
      |> get_field(relation_field_atom)
      |> try_force_int()

    image_from_changeset = get_field(changeset, assigns.field.field)
    image = socket.assigns.image

    {socket, image} =
      cond do
        is_nil(image) && image_id ->
          # we have an image in the changeset, but no loaded image
          {:ok, image} = Brando.Images.get_image(image_id)

          {socket
           |> assign(:image, image)
           |> assign(:image_id, image_id)
           |> assign(:focal, {image.focal.x, image.focal.y}), image}

        image && to_string(image.id) != to_string(image_id) && image_id != nil ->
          # we have a loaded image, but it does not match the changeset image
          # load the changeset image
          {:ok, image} = Brando.Images.get_image(image_id)

          {socket
           |> assign(:image, image)
           |> assign(:image_id, image_id)
           |> assign(:focal, {image.focal.x, image.focal.y}), image}

        image && image.id == nil && image_id == nil ->
          # no loaded image, no image_id in changeset
          # try to fetch by path?

          image_id =
            changeset
            |> EctoNestedChangeset.get_at(full_path_fk)
            |> try_force_int()

          {:ok, image} = Brando.Images.get_image(image_id)

          {socket
           |> assign(:image, image)
           |> assign(:image_id, image_id), image}

        image_id == nil && image != nil ->
          # reset image to nil
          {socket
           |> assign(:focal, {nil, nil})
           |> assign(:image_id, nil)
           |> assign(:image, nil), nil}

        image_id != socket.assigns.image_id ->
          {assign(socket, :image_id, image_id), image}

        image && socket.assigns.focal != {nil, nil} &&
            socket.assigns.focal != {image.focal.x, image.focal.y} ->
          {:ok, image} = Brando.Images.get_image(image_id)

          {socket
           |> assign(:image, image)
           |> assign(:focal, {image.focal.x, image.focal.y}), image}

        image && image_from_changeset && socket.assigns.focal != {nil, nil} &&
            {image_from_changeset.focal.x, image_from_changeset.focal.y} != socket.assigns.focal ->
          # we have an image, and an image from the changeset where the changeset image
          # has an updated focal value. lets just grab the image from changeset
          {socket
           |> assign(:image, image_from_changeset)
           |> assign(:focal, {image_from_changeset.focal.x, image_from_changeset.focal.y}), image}

        # we have an image, and an image from the changeset, but the title, credits or alt has changed
        image && image_from_changeset &&
            (image.title != image_from_changeset.title ||
               image.credits != image_from_changeset.credits ||
               image.alt != image_from_changeset.alt) ->
          {assign(socket, :image, image_from_changeset), image_from_changeset}

        true ->
          if image && image.status == :unprocessed do
            # if the image is unprocessed, we can try to reload and see if it's done.
            {:ok, image} = Brando.Images.get_image(image_id)

            {socket
             |> assign(:image, image)
             |> assign(:focal, {image.focal.x, image.focal.y}), image}
          else
            {socket, image}
          end
      end

    file_name = if is_map(image) && image.path, do: Path.basename(image.path)

    {:ok,
     socket
     |> prepare_input_component()
     |> assign(:file_name, file_name)
     |> assign_new(:editable, fn -> Keyword.get(socket.assigns.opts, :editable, true) end)
     |> assign_new(:upload_field, fn -> socket.assigns.parent_uploads[assigns.field.field] end)
     |> assign_new(:relation_field, fn -> relation_field end)}
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
        relation
      >
        <div>
          <div class={["input-image", @small && "small", @square && "square"]}>
            <.image_preview
              image={@image}
              field={@field}
              relation_field={@relation_field}
              click={@editable && open_image(@myself)}
              editable={@editable}
              file_name={@file_name}
            />
          </div>
        </div>
      </Form.field_base>
      <div :if={!@editable} class={["input-image", @small && "small", @square && "square"]}>
        <.image_preview
          image={@image}
          field={@field}
          relation_field={@relation_field}
          click={@editable && open_image(@myself)}
          editable={@editable}
          file_name={@file_name}
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
    image = socket.assigns.image
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

    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: {"image", form.data.__struct__, field_name},
      event_target: myself,
      multi: false,
      selected_images: []
    )

    form_id = "#{module.__naming__().singular}_form"

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
      |> assign_new(:image_id, fn ->
        if assigns[:image] do
          assigns[:image].id
        end
      end)

    ~H"""
    <div class="image-wrapper-compact">
      <Input.input
        :if={@editable}
        type={:hidden}
        field={@relation_field}
        value={@value || @image_id}
        publish={@publish}
      />
      <%= if @image do %>
        <%= if @image.status == :processed do %>
          <Content.image image={@image} size={(@size && @size) || (@editable && :thumb) || :smallest} />
        <% else %>
          <div class="img-placeholder">
            <svg
              class="spin"
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              width="24"
              height="24"
            >
              <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
            </svg>
          </div>
        <% end %>
        <div :if={@editable} class="image-info">
          <div class="info-wrapper">
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
          {gettext("No image associated with field")}
          <button
            class="tiny"
            type="button"
            phx-click={@click}
            phx-value-id={"edit-image-#{@field.id}"}
          >
            {gettext("Add image")}
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
