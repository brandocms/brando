defmodule BrandoAdmin.Components.Form.Input.RenderVar do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext
  import Ecto.Changeset

  alias Brando.Utils
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input

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

  def preload(all_assigns) do
    {image_ids, cmp_imgs} =
      Enum.reduce(all_assigns, {[], []}, fn
        %{id: id, var: %{data: %{type: "image", value_id: image_id}}}, {image_ids, cmp_imgs} ->
          {[image_id | image_ids], [{id, image_id} | cmp_imgs]}

        _, acc ->
          acc
      end)

    if image_ids == [] do
      all_assigns
    else
      {:ok, images} = Brando.Images.list_images(%{filter: %{ids: image_ids}})
      mapped_images = images |> Enum.map(&{&1.id, &1}) |> Map.new()
      mapped_ids = Map.new(cmp_imgs)

      Enum.map(all_assigns, fn assigns ->
        case Map.get(mapped_ids, assigns.id) do
          nil -> assigns
          key -> Map.put(assigns, :original_image, Map.get(mapped_images, key))
        end
      end)
    end
  end

  def mount(socket) do
    {:ok, assign(socket, visible: false)}
  end

  def update(%{var: var} = assigns, socket) do
    changeset = var.source
    important = get_field(changeset, :important)
    render = Map.get(assigns, :render, :all)
    edit = Map.get(assigns, :edit, false)
    target = Map.get(assigns, :target, nil)

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
          if assigns[:original_image] do
            assigns[:original_image]
          else
            case Brando.Images.get_image(value) do
              {:ok, image} -> image
              {:error, _} -> nil
            end
          end
        end)
      else
        assign_new(socket, :image, fn -> nil end)
      end

    {:ok,
     socket
     |> assign(:id, assigns.id)
     |> assign(:edit, edit)
     |> assign(:target, target)
     |> assign(:should_render?, should_render?)
     |> assign(:important, important)
     |> assign(:label, get_field(changeset, :label))
     |> assign(:key, v(var, :key))
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

  defp control_value("select", value) when is_binary(value), do: value
  defp control_value("select", _value), do: ""

  defp control_value("html", value) when is_binary(value), do: value
  defp control_value("html", _value), do: "<p></p>"

  defp control_value("image", value) when is_binary(value), do: nil
  defp control_value("image", value) when is_boolean(value), do: nil
  defp control_value("image", value), do: value

  def render(assigns) do
    ~H"""
      <div id={@id} class={render_classes(["variable", v(@var, :type)])}>
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
                <Input.toggle form={@var} field={:marked_as_deleted} label={gettext "Marked as deleted"} />
                <Input.toggle form={@var} field={:important} label={gettext "Important"} />
                <Input.text form={@var} field={:key} label={gettext "Key"} />
                <Input.text form={@var} field={:label} label={gettext "Label"} />
                <Input.text form={@var} field={:instructions} label={gettext "Instructions"} />
                <Input.text form={@var} field={:placeholder} label={gettext "Placeholder"} />
                <Input.radios form={@var} field={:type} label={gettext "Type"} opts={[options: [
                  %{label: "Boolean", value: "boolean"},
                  %{label: "Color", value: "color"},
                  %{label: "Datetime", value: "datetime"},
                  %{label: "Html", value: "html"},
                  %{label: "String", value: "string"},
                  %{label: "Select", value: "select"},
                  %{label: "Text", value: "text"},
                  %{label: "Image", value: "image"},
                ]]} />

                <.render_value_inputs
                  edit
                  id={@id}
                  type={@type}
                  var={@var}
                  image={@image}
                  images={@images}
                  label={@label}
                  value_id={@value_id}
                  placeholder={@placeholder}
                  instructions={@instructions}
                  myself={@myself} />

                <%= case @type do %>
                  <% "color" -> %>
                    <Input.toggle form={@var} field={:picker} label={gettext "Allow picking custom colors"} />
                    <Input.toggle form={@var} field={:opacity} label={gettext "Allow setting opacity"} />
                    <Input.number form={@var} field={:palette_id} label={gettext "ID of palette to choose colors from"} />

                  <% "select" -> %>
                    <Form.field_base
                      form={@var}
                      field={:options}
                      label="Options"
                      instructions=""
                      left_justify_meta>
                      <Form.label
                        form={@var}
                        field={:options}>
                        <%= for opt <- inputs_for(@var, :options) do %>
                          <Input.text form={opt} field={:label} label={gettext "Label"} />
                          <Input.text form={opt} field={:value} label={gettext "Value"} />
                        <% end %>
                      </Form.label>
                      <button
                        type="button"
                        class="secondary"
                        phx-click={JS.push("add_select_var_option", value: %{var_key: @key}, target: @target)}>
                        <%= gettext("Add option") %>
                      </button>
                    </Form.field_base>

                  <% _ -> %>

                <% end %>
              </div>
            </div>
          <% else %>
            <div id={"#{@var.id}-value"}>
              <Input.input type={:hidden} form={@var} field={:key} />
              <Input.input type={:hidden} form={@var} field={:label} />
              <Input.input type={:hidden} form={@var} field={:type} />
              <Input.input type={:hidden} form={@var} field={:important} />
              <Input.input type={:hidden} form={@var} field={:instructions} />
              <Input.input type={:hidden} form={@var} field={:placeholder} />

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
    assigns = assign_new(assigns, :edit, fn -> false end)

    ~H"""
    <div class="brando-input">
      <%= case @type do %>
        <% "string" -> %>
          <Input.text form={@var} field={:value} label={@label} placeholder={@placeholder} instructions={@instructions} />

        <% "text" -> %>
          <Input.textarea form={@var} field={:value} label={@label} placeholder={@placeholder} instructions={@instructions} />

        <% "boolean" -> %>
          <Input.toggle form={@var} field={:value} label={@label} instructions={@instructions} />

        <% "color" -> %>
          <Input.color
            form={@var}
            field={:value}
            label={@label}
            placeholder={@placeholder}
            instructions={@instructions}
            opts={[
              opacity: input_value(@var, :opacity),
              picker: input_value(@var, :picker),
              palette_id: input_value(@var, :palette_id),
            ]} />
          <%= unless @edit do %>
            <Input.input type={:hidden} form={@var} field={:picker} />
            <Input.input type={:hidden} form={@var} field={:opacity} />
            <Input.input type={:hidden} form={@var} field={:palette_id} />
          <% end %>

        <% "datetime" -> %>
          <Input.datetime form={@var} field={:value} label={@label} instructions={@instructions} />

        <% "html" -> %>
          <Input.rich_text form={@var} field={:value} label={@label} instructions={@instructions} />

        <% "select" -> %>
          <.live_component module={Input.Select}
            id={"#{@var.id}-select"}
            label={@label}
            form={@var}
            field={:value}
            opts={[options: input_value(@var, :options) || []]}
          />

          <%= for opt <- inputs_for(@var, :options) do %>
            <Input.hidden form={opt} field={:label} />
            <Input.hidden form={opt} field={:value} />
          <% end %>

        <% "image" -> %>
          <Form.field_base
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
            </div>
          </Form.field_base>
      <% end %>
    </div>
    """
  end

  def image_modal(assigns) do
    ~H"""
    <Content.modal title={gettext "Image"} id={"var-#{@form.id}-image-config"}>
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
          <div class="button-group-vertical">
            <button type="button" class="secondary" phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}>
              <%= gettext("Select image") %>
            </button>

            <button type="button" class="danger" phx-click={JS.push("reset_image", target: @myself)}>
              <%= gettext("Reset image") %>
            </button>
          </div>
        </div>
      </div>
    </Content.modal>
    """
  end

  def handle_event("set_target", _, %{assigns: %{myself: myself}} = socket) do
    send_update(
      BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: "default",
      event_target: myself,
      multi: false,
      selected_images: []
    )

    {:noreply, socket}
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
