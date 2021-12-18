defmodule BrandoAdmin.Components.Form.Input.Image do
  use BrandoAdmin, :live_component

  import Ecto.Changeset
  import Brando.Gettext

  alias BrandoAdmin.Components.Form.FieldBase
  alias Brando.Images
  alias Brando.Utils

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

  # data show_edit_meta, :boolean, default: false
  # data focal, :any
  # data image, :any
  # data file_name, :any
  # data upload_field, :any
  # data relation_field, :atom

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:relation_field, fn -> nil end)
     |> assign_new(:image, fn -> nil end)
     |> assign_new(:opts, fn -> [] end)
     |> assign_new(:previous_image_id, fn -> nil end)
     |> assign_new(:label, fn -> nil end)
     |> assign_new(:instructions, fn -> nil end)
     |> assign_new(:placeholder, fn -> nil end)}
  end

  def update(assigns, socket) do
    relation_field = String.to_existing_atom("#{assigns.field}_id")

    image_id =
      assigns.form.source
      |> get_field(relation_field)
      |> try_force_int()

    previous_image_id = Map.get(socket.assigns, :previous_image_id)
    image = get_image(Map.get(socket.assigns, :image), image_id, previous_image_id)

    focal =
      if is_map(image) && image.path,
        do: Map.get(image, :focal, %Images.Focal{}),
        else: nil

    file_name = if is_map(image) && image.path, do: Path.basename(image.path), else: nil

    {:ok,
     socket
     |> assign(assigns)
     |> prepare_input_component()
     |> assign(:image, image)
     |> assign(:image_id, image_id)
     |> assign(:previous_image_id, image_id)
     |> assign(:file_name, file_name)
     |> assign(:upload_field, assigns.uploads[assigns.field])
     |> assign(:relation_field, relation_field)
     |> assign(:focal, focal)}
  end

  def try_force_int(str) when is_binary(str), do: String.to_integer(str)
  def try_force_int(int) when is_integer(int), do: int
  def try_force_int(val), do: val

  def get_image(nil, nil, _) do
    nil
  end

  def get_image(nil, image_id, previous_image_id) when image_id == previous_image_id do
    case Images.get_image(image_id) do
      {:ok, image} -> image
      {:error, _} -> nil
    end
  end

  def get_image(_image, nil, _) do
    nil
  end

  def get_image(image, image_id, previous_image_id) when image_id == previous_image_id do
    image
  end

  def get_image(_, image_id, _) do
    case Images.get_image(image_id) do
      {:ok, image} -> image
      {:error, _} -> nil
    end
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
        relation>
        <div>
          <div class="input-image">
            <%= if @image && @image.path do %>
              <.image_preview
                image={@image}
                form={@form}
                field={@field}
                relation_field={@relation_field}
                click={open_image(@myself)}
                file_name={@file_name} />
            <% else %>
              <.empty_preview
                form={@form}
                field={@field}
                relation_field={@relation_field}
                click={open_image(@myself)} />
            <% end %>
          </div>
        </div>
      </FieldBase.render>
    </div>
    """
  end

  def open_image(js \\ %JS{}, target) do
    js
    |> JS.push("open_image", target: target)
    |> toggle_drawer("#image-drawer")
  end

  def handle_event(
        "open_image",
        _,
        %{
          assigns: %{
            form: form,
            field: field,
            relation_field: relation_field,
            image_id: image_id,
            image: image
          }
        } = socket
      ) do
    path =
      Regex.scan(~r/\[(\w+)\]/, form.name, capture: :all_but_first)
      |> Enum.map(&(List.first(&1) |> String.to_existing_atom()))

    module = form.source.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      edit_image: %{
        id: image_id,
        path: path,
        field: field,
        relation_field: relation_field,
        image: image
      }
    )

    {:noreply, socket}
  end

  def empty_preview(assigns) do
    ~H"""
    <div class="image-wrapper-compact">
      <%= hidden_input @form, @relation_field, value: "" %>

      <div class="img-placeholder">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>
      </div>

      <div class="image-info">
        <%= gettext "No image associated with field" %>
        <button
          class="btn-small"
          type="button"
          phx-click={@click}
          phx-value-id={"edit-image-#{@form.id}-#{@field}"}><%= gettext "Add image" %></button>
      </div>
    </div>
    """
  end

  @doc """
  Show preview if we have an image with a path
  """
  def image_preview(assigns) do
    assigns = assign_new(assigns, :value, fn -> nil end)

    ~H"""
    <div class="image-wrapper-compact">
      <%= hidden_input @form, @relation_field, value: @value && @value || @image.id %>

      <%= if @image.status == :processed do %>
        <img
          width="25"
          height="25"
          src={"#{Utils.img_url(@image, :thumb, prefix: Utils.media_url())}"} />
      <% else %>
        <div class="img-placeholder">
          <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z"/></svg>
        </div>
      <% end %>

      <div class="image-info">
        <%= @file_name %> — <%= @image.width %>&times;<%= @image.height %>
        <%= if @image.title do %>
          <div class="title"><%= gettext "Caption" %>: <%= @image.title %></div>
        <% end %>
        <button
          class="btn-small"
          type="button"
          phx-click={@click}>
          <%= gettext "Edit image" %>
        </button>
      </div>
    </div>
    """
  end
end
