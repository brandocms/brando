defmodule BrandoAdmin.Components.Form.Input.Gallery.ImageConfig do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input

  def update(assigns, socket) do
    config = assigns.config || %{}

    form_data = %{
      "title" => Map.get(config, "title"),
      "alt" => Map.get(config, "alt"),
      "credits" => Map.get(config, "credits")
    }

    form = to_form(form_data, as: "config")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit="save_config" phx-target={@myself}>
        <div class="panels">
          <div class="panel">
            <figure>
              <Content.image image={@image} size={:smallest} />
            </figure>
          </div>
          <div class="panel">
            <Input.override_text
              field={@form[:title]}
              label={gettext("Title")}
              default_value={@image.title || ""}
              target={@myself}
            />

            <Input.override_text
              field={@form[:alt]}
              label={gettext("Alt text")}
              default_value={@image.alt || ""}
              target={@myself}
            />

            <Input.override_text
              field={@form[:credits]}
              label={gettext("Credits")}
              default_value={@image.credits || ""}
              target={@myself}
            />
          </div>
        </div>

        <div class="button-group">
          <button type="submit" class="primary">{gettext("Save")}</button>
          <button type="button" phx-click="cancel_config" phx-target={@myself}>{gettext("Cancel")}</button>
        </div>
      </form>
    </div>
    """
  end

  def handle_event("reset_override", %{"field" => field_name}, socket) do
    form = socket.assigns.form
    updated_data = Map.put(form.source, field_name, nil)
    updated_form = to_form(updated_data, as: "config")

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("save_config", params, socket) do
    config_params = params["config"] || %{}

    config =
      %{}
      |> maybe_put_config("title", config_params["title"])
      |> maybe_put_config("alt", config_params["alt"])
      |> maybe_put_config("credits", config_params["credits"])

    send_update(socket.assigns.gallery_component, %{
      id: socket.assigns.gallery_component_id,
      event: "update_object_config",
      gallery_object_index: socket.assigns.gallery_object_index,
      config: config
    })

    {:noreply, socket}
  end

  def handle_event("cancel_config", _, socket) do
    send_update(socket.assigns.gallery_component, %{
      id: socket.assigns.gallery_component_id,
      event: "close_config_modal"
    })

    {:noreply, socket}
  end

  defp maybe_put_config(config, _key, nil), do: config
  defp maybe_put_config(config, _key, ""), do: config
  defp maybe_put_config(config, key, value), do: Map.put(config, key, value)
end
