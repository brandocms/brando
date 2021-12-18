defmodule BrandoAdmin.Components.Form.Input.RenderVar do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext
  import Ecto.Changeset

  alias Brando.Utils
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Modal

  # prop var, :any
  # prop render, :atom, values: [:all, :only_important, :only_regular], default: :all
  # prop edit, :boolean, default: false

  # data should_render?, :boolean
  # data label, :string
  # data type, :string
  # data instructions, :string
  # data placeholder, :string
  # data value, :any
  # data visible, :boolean

  def v(form, field) do
    get_field(form.source, field)
  end

  def mount(socket) do
    {:ok, assign(socket, visible: false)}
  end

  def update(%{var: var} = assigns, socket) do
    changeset = var.source
    important = get_field(changeset, :important)
    render = Map.get(assigns, :render, :all)
    edit = Map.get(assigns, :edit, false)

    should_render? =
      cond do
        render == :all -> true
        render == :only_important and important -> true
        render == :only_regular and !important -> true
        true -> false
      end

    type = get_field(changeset, :type)

    value =
      if type == "image" do
        get_field(changeset, :value_id)
      else
        get_field(changeset, :value)
      end

    value = control_value(type, value)

    socket =
      if type == "image" do
        assign_new(socket, :image, fn ->
          (value && Brando.Images.get_image!(value)) || nil
        end)
      else
        assign_new(socket, :image, fn -> nil end)
      end

    {:ok,
     socket
     |> assign(:edit, edit)
     |> assign(:should_render?, should_render?)
     |> assign(:important, important)
     |> assign(:label, get_field(changeset, :label))
     |> assign(:type, type)
     |> assign(:value, value)
     |> assign_new(:images, fn -> nil end)
     |> assign_new(:value_id, fn -> value end)
     |> assign(:instructions, get_field(changeset, :instructions))
     |> assign(:placeholder, get_field(changeset, :placeholder))
     |> assign(:var, var)}
  end

  defp control_value("string", value) when is_binary(value), do: value
  defp control_value("string", _value), do: ""

  defp control_value("text", value) when is_binary(value), do: value
  defp control_value("text", _value), do: ""

  defp control_value("datetime", %DateTime{} = value), do: value
  defp control_value("datetime", %Date{} = value), do: value
  defp control_value("datetime", _value), do: DateTime.utc_now()

  defp control_value("boolean", value) when is_boolean(value), do: value
  defp control_value("boolean", _value), do: false

  defp control_value("color", "#" <> value), do: "##{value}"
  defp control_value("color", _value), do: "#000000"

  defp control_value("html", value) when is_binary(value), do: value
  defp control_value("html", _value), do: "<p></p>"

  defp control_value("image", value) when is_binary(value), do: nil
  defp control_value("image", value) when is_boolean(value), do: nil
  defp control_value("image", value), do: value

  def render(assigns) do
    ~H"""
      <div class={render_classes(["variable", v(@var, :type)])}>
        <%= if @should_render? do %>
          <%= if @edit do %>
            <div id={"#{@var.id}-edit"}>
              <div class="variable-header" phx-click={JS.push("toggle_visible", target: @myself)}>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm-2.29-2.333A17.9 17.9 0 0 1 8.027 13H4.062a8.008 8.008 0 0 0 5.648 6.667zM10.03 13c.151 2.439.848 4.73 1.97 6.752A15.905 15.905 0 0 0 13.97 13h-3.94zm9.908 0h-3.965a17.9 17.9 0 0 1-1.683 6.667A8.008 8.008 0 0 0 19.938 13zM4.062 11h3.965A17.9 17.9 0 0 1 9.71 4.333 8.008 8.008 0 0 0 4.062 11zm5.969 0h3.938A15.905 15.905 0 0 0 12 4.248 15.905 15.905 0 0 0 10.03 11zm4.259-6.667A17.9 17.9 0 0 1 15.973 11h3.965a8.008 8.008 0 0 0-5.648-6.667z"/></svg>
                <div class="variable-key">
                  <%= v(@var, :key) %>
                  <span><%= v(@var, :type) %></span>
                </div>
              </div>

              <div class={render_classes(["variable-content", hidden: !@visible])}>
                <Input.Toggle.render form={@var} field={:marked_as_deleted} label={gettext "Marked as deleted"} />
                <Input.Toggle.render form={@var} field={:important} label={gettext "Important"} />
                <Input.Text.render form={@var} field={:key} label={gettext "Key"} />
                <Input.Text.render form={@var} field={:label} label={gettext "Label"} />
                <Input.Text.render form={@var} field={:instructions} label={gettext "Instructions"} />
                <Input.Text.render form={@var} field={:placeholder} label={gettext "Placeholder"} />
                <Input.Radios.render form={@var} field={:type} label={gettext "Type"} opts={[options: [
                  %{label: "Boolean", value: "boolean"},
                  %{label: "Color", value: "color"},
                  %{label: "Datetime", value: "datetime"},
                  %{label: "Html", value: "html"},
                  %{label: "String", value: "string"},
                  %{label: "Text", value: "text"},
                  %{label: "Image", value: "image"},
                ]]} />

                <.render_value_inputs
                  type={@type}
                  var={@var}
                  image={@image}
                  images={@images}
                  label={@label}
                  value_id={@value_id}
                  placeholder={@placeholder}
                  instructions={@instructions}
                  myself={@myself} />
              </div>
            </div>
          <% else %>
            <div id={"#{@var.id}-value"}>
              <%= hidden_input @var, :key %>
              <%= hidden_input @var, :label %>
              <%= hidden_input @var, :type %>
              <%= hidden_input @var, :important %>
              <%= hidden_input @var, :instructions %>
              <%= hidden_input @var, :placeholder %>

              <.render_value_inputs
                type={@type}
                var={@var}
                image={@image}
                images={@images}
                label={@label}
                value_id={@value_id}
                placeholder={@placeholder}
                instructions={@instructions}
                myself={@myself} />
            </div>
          <% end %>
        <% end %>
      </div>
    """
  end

  def render_value_inputs(assigns) do
    ~H"""
    <div class="brando-input">
      <%= case @type do %>
        <% "string" -> %>
          <Input.Text.render form={@var} field={:value} label={@label} placeholder={@placeholder} instructions={@instructions} />

        <% "text" -> %>
          <Input.Textarea.render form={@var} field={:value} label={@label} placeholder={@placeholder} instructions={@instructions} />

        <% "boolean" -> %>
          <Input.Toggle.render form={@var} field={:value} label={@label} instructions={@instructions} />

        <% "color" -> %>
          <Input.Text.render form={@var} field={:value} label={@label} placeholder={@placeholder} instructions={@instructions} />

        <% "datetime" -> %>
          <Input.Datetime.render form={@var} field={:value} label={@label} instructions={@instructions} />

        <% "html" -> %>
          <Input.RichText.render form={@var} field={:value} label={@label} instructions={@instructions} />

        <% "image" -> %>
          <FieldBase.render
            form={@var}
            field={:value_id}
            label={@label}
            instructions={@instructions}>
            <div class="input-image">
              <%= if @image do %>
                <Input.Image.image_preview
                  image={@image}
                  form={@var}
                  field={:value}
                  value={@value_id}
                  relation_field={:value_id}
                  click={show_modal("#var-#{@var.id}-image-config")}
                  file_name={(@image && @image.path) && Path.basename(@image.path)} />
              <% else %>
                <Input.Image.empty_preview
                  form={@var}
                  field={:value}
                  relation_field={:value_id}
                  click={show_modal("#var-#{@var.id}-image-config")} />
              <% end %>
              <.image_modal form={@var} image={@image} myself={@myself} />
              <.image_picker_modal images={@images} form={@var} myself={@myself} />
            </div>
          </FieldBase.render>
      <% end %>
    </div>
    """
  end

  def image_picker_modal(assigns) do
    ~H"""
    <.live_component module={Modal} title={gettext "Pick image"} id={"var-#{@form.id}-image-picker"}>
      <div class="image-picker-images">
        <%= if @images do %>
          <%= for image <- @images do %>
            <div class="image-picker-image" phx-click={JS.push("select_image", target: @myself, value: %{id: image.id}) |> hide_modal("#var-#{@form.id}-image-picker")}>
              <img src={"/media/#{image.sizes["thumb"]}"} />
            </div>
          <% end %>
        <% end %>
      </div>
    </.live_component>
    """
  end

  def image_modal(assigns) do
    ~H"""
    <.live_component module={Modal} title={gettext "Image"} id={"var-#{@form.id}-image-config"}>
      <div class="panels">
        <div class="panel">
          <%= if @image && @image.path do %>
            <img
              width={"#{@image.width}"}
              height={"#{@image.height}"}
              src={"#{Utils.img_url(@image, :original, prefix: Utils.media_url())}"} />

            <div class="image-info">
              Path: <%= @image.path %><br>
              Dimensions: <%= @image.width %>&times;<%= @image.height %><br>
            </div>
          <% end %>
          <%= if !@image do %>
            <div
              id={"#{@form.id}-legacy-uploader"}
              class="input-image"
              phx-hook="Brando.LegacyImageUpload"
              data-text-uploading={gettext("Uploading...")}
              data-block-uid={"var-#{@form.id}"}
              data-upload-event-target={@myself}>
              <input class="file-input" type="file" />
              <div class="img-placeholder empty upload-canvas">
                <div class="placeholder-wrapper">
                  <div class="svg-wrapper">
                    <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                      <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none"/>
                      <polygon class="plus" points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"/>
                      <path d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z" transform="translate(0 0)"/>
                      <circle cx="8" cy="9" r="2"/>
                    </svg>
                  </div>
                </div>
                <div class="instructions">
                  <span><%= gettext("Click or drag an image &uarr; to upload") |> raw() %></span>
                </div>
              </div>
            </div>
          <% end %>
        </div>
        <div class="panel">
          <%# Input.RichText.render form={@block_data} field={:title} label={gettext "Title"} %>
          <%# Input.Text.render form={@block_data} field={:alt} label={gettext "Alt"} %>

          <div class="button-group-vertical">
            <button type="button" class="secondary" phx-click={open_image_picker(@form.id, @myself)}>
              <%= gettext("Select image") %>
            </button>

            <button type="button" class="danger" phx-click={JS.push("reset_image", target: @myself)}>
              <%= gettext("Reset image") %>
            </button>
          </div>
        </div>
      </div>
    </.live_component>
    """
  end

  def open_image_picker(var_id, target) do
    %JS{}
    |> JS.push("assign_images", target: target)
    |> show_modal("#var-#{var_id}-image-picker")
  end

  def handle_event("assign_images", _, socket) do
    images =
      if socket.assigns.images do
        socket.assigns.images
      else
        Brando.Images.list_images(%{order: "desc inserted_at"}) |> elem(1)
      end

    {:noreply, assign(socket, :images, images)}
  end

  def handle_event(
        "reset_image",
        _,
        socket
      ) do
    {:noreply,
     socket
     |> assign(:image, nil)
     |> assign(:value_id, nil)}
  end

  def handle_event(
        "select_image",
        %{"id" => image_id},
        socket
      ) do
    image = Brando.Images.get_image!(image_id)

    {:noreply,
     socket
     |> assign(:value_id, image_id)
     |> assign(:image, image)}
  end

  def handle_event(
        "image_uploaded",
        %{"id" => image_id},
        socket
      ) do
    image = Brando.Images.get_image!(image_id)

    {:noreply,
     socket
     |> assign(:value_id, image_id)
     |> assign(:image, image)}
  end

  def handle_event("toggle_visible", _, socket) do
    {:noreply, update(socket, :visible, &(!&1))}
  end
end
