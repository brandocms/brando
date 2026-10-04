defmodule BrandoAdmin.Components.Form.Input.Gallery.ImageConfig do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog

  @caption_opts [extensions: ~w(p bold italic link)]

  def update(assigns, socket) do
    config = assigns.config || %{}

    form_data = %{
      "title" => Map.get(config, "title"),
      "alt" => Map.get(config, "alt"),
      "credits" => Map.get(config, "credits")
    }

    form = to_form(form_data, as: "config", id: assigns.id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:caption_opts, @caption_opts)
     |> assign(:form, form)}
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:modal_id, "#{assigns.gallery_component_id}-object-config-modal")
      |> assign(:filename, assigns.image && assigns.image.path && Path.basename(assigns.image.path))
      |> assign(:dimensions, dimensions(assigns.image))

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
            <Content.image image={@image} size={:smallest} />
          </figure>
          <div class="gallery-object-config-copy">
            <span :if={@filename} class="gallery-object-config-name">{@filename}</span>
            <span :if={@dimensions} class="gallery-object-config-meta">{@dimensions}</span>
          </div>
        </div>

        <p class="modal-muted gallery-object-config-note">
          {gettext("Customize this use of the image. Empty text overrides use the library values.")}
        </p>

        <div class="gallery-object-config-fields">
          <Input.rich_text
            field={@form[:title]}
            label={gettext("Caption")}
            default_value={Brando.Captions.library_html(Brando.Images.text(@image, :title, nil))}
            reset
            target={@myself}
            opts={@caption_opts}
          />

          <Input.override_text
            field={@form[:alt]}
            label={gettext("Alternative text")}
            default_value={Brando.Images.text(@image, :alt, nil) || ""}
            target={@myself}
          />

          <Input.override_text
            field={@form[:credits]}
            label={gettext("Credits")}
            default_value={Brando.Images.text(@image, :credits, nil) || ""}
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

  defp dimensions(%{width: width, height: height}) when is_integer(width) and is_integer(height),
    do: "#{width}\u00d7#{height}"

  defp dimensions(_), do: nil

  def handle_event("reset_override", %{"field" => field_name}, socket) do
    form = socket.assigns.form
    updated_data = Map.put(form.source, field_name, nil)
    updated_form = to_form(updated_data, as: "config", id: form.id)

    {:noreply, assign(socket, :form, updated_form)}
  end

  def handle_event("save_config", params, socket) do
    config_params = params["config"] || %{}

    config =
      %{}
      |> maybe_put_config("title", Brando.Captions.normalize(config_params["title"]))
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
end
