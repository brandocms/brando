defmodule BrandoAdmin.Components.Form.Input.Gallery.VideoConfig do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog

  @caption_opts [extensions: ~w(p bold italic link)]

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

    form = to_form(form_data, as: "config", id: assigns.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, form)
     |> assign(:caption_opts, @caption_opts)
     |> assign(:video, video)}
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:modal_id, "#{assigns.gallery_component_id}-object-config-modal")
      |> assign(:thumbnail, thumbnail(assigns.video))
      |> assign(:source, assigns.video.source_url)

    ~H"""
    <div>
      <%!-- Inside the entry form, so its submit is handled by the hook --%>
      <form
        id={"#{@id}-form"}
        class="gallery-object-config"
        phx-hook="Brando.DetachedForm"
        data-submit-event="save_config"
        data-on-submit={hide_modal("##{@modal_id}")}
      >
        <div class="gallery-object-config-media">
          <figure class="gallery-object-config-thumb">
            <Content.image :if={@thumbnail} image={@thumbnail} size={:smallest} />
            <div :if={!@thumbnail} class="video-placeholder">
              <.icon name="video" />
            </div>
          </figure>
          <div class="gallery-object-config-copy">
            <span class="gallery-object-config-name">{@video.title || gettext("Untitled video")}</span>
            <span :if={@source} class="gallery-object-config-meta">{@source}</span>
          </div>
        </div>

        <p class="modal-muted gallery-object-config-note">
          {gettext("Customize this use of the video. Empty text overrides use the library values.")}
        </p>

        <div class="gallery-object-config-fields">
          <Input.override_text
            field={@form[:title]}
            label={gettext("Title")}
            default_value={@video.title || ""}
            target={@myself}
          />

          <Input.rich_text
            field={@form[:caption]}
            label={gettext("Caption")}
            default_value={Brando.Captions.library_html(@video.title)}
            reset
            target={@myself}
            opts={@caption_opts}
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

        <footer class="modal-footer gallery-object-config-footer">
          <button
            type="button"
            class="secondary"
            phx-click={hide_modal("##{@modal_id}") |> JS.push("cancel_config", target: @myself)}
          >
            {gettext("Cancel")}
          </button>
          <button type="submit" class="primary">{gettext("Save")}</button>
        </footer>
      </form>
    </div>
    """
  end

  defp thumbnail(video) do
    if Brando.Utils.loaded_assoc?(video, :thumbnail), do: video.thumbnail
  end

  def handle_event("toggle_override", %{"field" => field_name, "default" => default_str}, socket) do
    default_val = default_str == "true"
    form = socket.assigns.form
    current_value = form[String.to_existing_atom(field_name)].value

    visual_state = if is_nil(current_value), do: default_val, else: current_value == true
    new_value = !visual_state

    updated_data = Map.put(form.source, field_name, new_value)
    updated_form = to_form(updated_data, as: "config", id: form.id)

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("reset_override", %{"field" => field_name}, socket) do
    form = socket.assigns.form
    updated_data = Map.put(form.source, field_name, nil)
    updated_form = to_form(updated_data, as: "config", id: form.id)

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("reset_override_group", %{"fields" => fields_str}, socket) do
    field_names = String.split(fields_str, ",")
    form = socket.assigns.form

    updated_data =
      Enum.reduce(field_names, form.source, fn field, acc ->
        Map.put(acc, field, nil)
      end)

    updated_form = to_form(updated_data, as: "config", id: form.id)

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("save_config", params, socket) do
    config_params = params["config"] || %{}

    config =
      %{}
      |> maybe_put_config("title", config_params["title"])
      |> maybe_put_config("caption", Brando.Captions.normalize(config_params["caption"]))
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

  # The caption's rich text pushes these to its target.
  def handle_event("focus", _, socket), do: {:noreply, socket}

  def handle_event("tiptap_link_dialog", params, socket) do
    TipTapLinkDialog.open(params, content_language(socket))
    {:noreply, socket}
  end

  def handle_event("tiptap_link_result", params, socket) do
    TipTapLinkDialog.receive_result(params)
    {:noreply, socket}
  end

  def handle_event("cancel_config", _, socket) do
    send_update(socket.assigns.gallery_component, %{
      id: socket.assigns.gallery_component_id,
      event: "close_config_modal"
    })

    {:noreply, socket}
  end

  defp content_language(%{assigns: %{current_user: %{config: %{content_language: language}}}}), do: language
  defp content_language(_socket), do: Brando.config(:default_language)

  defp maybe_put_config(config, _key, nil), do: config
  defp maybe_put_config(config, _key, ""), do: config
  defp maybe_put_config(config, key, value), do: Map.put(config, key, value)

  defp maybe_put_bool_config(config, _key, nil), do: config
  defp maybe_put_bool_config(config, key, value), do: Map.put(config, key, value == "true")
end
