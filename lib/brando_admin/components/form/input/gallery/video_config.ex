defmodule BrandoAdmin.Components.Form.Input.Gallery.VideoConfig do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input

  def update(assigns, socket) do
    config = assigns.config || %{}
    video = assigns.video

    form_data = %{
      "title" => Map.get(config, "title"),
      "caption" => Map.get(config, "caption"),
      "autoplay" => Map.get(config, "autoplay"),
      "loop" => Map.get(config, "loop"),
      "muted" => Map.get(config, "muted"),
      "controls" => Map.get(config, "controls"),
      "preload" => Map.get(config, "preload")
    }

    form = to_form(form_data, as: "config")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)
     |> assign(:video, video)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <form phx-submit="save_config" phx-target={@myself}>
        <div class="panels">
          <div class="panel">
            <figure>
              <%= if Brando.Utils.loaded_assoc?(@video, :thumbnail) and @video.thumbnail do %>
                <Content.image image={@video.thumbnail} size={:smallest} />
              <% else %>
                <div class="video-placeholder">
                  <.icon name="hero-video-camera" />
                </div>
              <% end %>
            </figure>
          </div>
          <div class="panel">
            <Input.override_text
              field={@form[:title]}
              label={gettext("Title")}
              default_value={@video.title || ""}
              target={@myself}
            />

            <Input.override_text
              field={@form[:caption]}
              label={gettext("Caption")}
              default_value={@video.caption || ""}
              target={@myself}
            />

            <Input.override_toggle_group
              label={gettext("Video playback")}
              fields={[
                {@form[:autoplay], gettext("Autoplay"), @video.autoplay || false},
                {@form[:loop], gettext("Loop"), @video.loop || false},
                {@form[:muted], gettext("Muted"), Map.get(@video, :muted, false)},
                {@form[:controls], gettext("Controls"), @video.controls || false},
                {@form[:preload], gettext("Preload"), @video.preload || false}
              ]}
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

  def handle_event("toggle_override", %{"field" => field_name, "default" => default_str}, socket) do
    default_val = default_str == "true"
    form = socket.assigns.form
    current_value = form[String.to_existing_atom(field_name)].value

    visual_state = if is_nil(current_value), do: default_val, else: current_value == true
    new_value = !visual_state

    updated_data = Map.put(form.source, field_name, new_value)
    updated_form = to_form(updated_data, as: "config")

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("reset_override", %{"field" => field_name}, socket) do
    form = socket.assigns.form
    updated_data = Map.put(form.source, field_name, nil)
    updated_form = to_form(updated_data, as: "config")

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("reset_override_group", %{"fields" => fields_str}, socket) do
    field_names = String.split(fields_str, ",")
    form = socket.assigns.form

    updated_data =
      Enum.reduce(field_names, form.source, fn field, acc ->
        Map.put(acc, field, nil)
      end)

    updated_form = to_form(updated_data, as: "config")

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("save_config", params, socket) do
    config_params = params["config"] || %{}

    config =
      %{}
      |> maybe_put_config("title", config_params["title"])
      |> maybe_put_config("caption", config_params["caption"])
      |> maybe_put_bool_config("autoplay", config_params["autoplay"])
      |> maybe_put_bool_config("loop", config_params["loop"])
      |> maybe_put_bool_config("muted", config_params["muted"])
      |> maybe_put_bool_config("controls", config_params["controls"])
      |> maybe_put_bool_config("preload", config_params["preload"])

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

  defp maybe_put_bool_config(config, _key, nil), do: config
  defp maybe_put_bool_config(config, key, value), do: Map.put(config, key, value == "true")
end
