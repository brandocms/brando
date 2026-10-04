defmodule BrandoAdmin.Components.Form.Input.ImageFocal do
  @moduledoc """
  `inputs_for :focal` on an image's own form: the image, with its focal point
  set by clicking it, as in the image drawer, instead of two number fields.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Form.Input.Image.FocalPoint
  alias BrandoAdmin.Components.Form.Primitives
  alias Phoenix.LiveView.JS

  def update(assigns, socket) do
    image = Ecto.Changeset.apply_changes(assigns.field.form.source)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:image, image)
     |> assign(:form, assigns.field.form)}
  end

  def render(assigns) do
    ~H"""
    <fieldset class="image-focal-field">
      <Primitives.field_base field={@field} label={@label} instructions={gettext("Click the image to set its focal point.")}>
        <figure :if={@image.path} class="grid-overlay image-focal-figure">
          <.live_component
            module={FocalPoint}
            id={"#{@id}-focal-point"}
            image={%{image: @image}}
            form_id={@form.id}
            form_name={@form.name}
          />
          <img
            width={@image.width}
            height={@image.height}
            src={Brando.Utils.img_url(@image, :original, prefix: Brando.Utils.media_url())}
            alt=""
          />
        </figure>
        <button
          :if={@image.path && @form_cid}
          type="button"
          class="media-button image-focal-edit"
          phx-click={JS.push("open_own_image_editor", target: @form_cid) |> open_image_editor_drawer()}
        >
          <.icon name="scissors" />{gettext("Edit/Crop")}
        </button>
      </Primitives.field_base>
    </fieldset>
    """
  end
end
