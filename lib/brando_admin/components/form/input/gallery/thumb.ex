defmodule BrandoAdmin.Components.Form.Input.Gallery.Thumb do
  @moduledoc """
  The grid thumbnail for one gallery object, with its remove button.

  Rendered by both gallery editors. The markup was byte-identical in each; only
  the lookup differed, and the difference was a bug — `Input.GalleryObjects`
  matched on truthiness, so an empty-string `image_id` compared equal to a nil
  one (`to_string(nil) == to_string("")`) and could render a *different*
  object's thumbnail. `Input.Gallery`'s guard is the correct one and is what
  this uses.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  import Brando.Utils, only: [loaded_assoc?: 2]

  alias Brando.Utils
  alias Phoenix.LiveView.JS

  attr :gallery_objects, :list, required: true
  attr :gallery_object_field, :any, required: true
  attr :form_name, :string, required: true

  def thumb(assigns) do
    assigns = assign(assigns, :gallery_object, find(assigns))

    ~H"""
    <div :if={@gallery_object}>
      <%= if Map.get(@gallery_object, :image_id) && loaded_assoc?(@gallery_object, :image) do %>
        <%= if @gallery_object.image.status == :processed do %>
          <img
            width="25"
            height="25"
            src={"#{Utils.img_url(@gallery_object.image, :thumb, prefix: Utils.media_url())}"}
          />
        <% else %>
          <div class="img-placeholder">
            <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
              <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
            </svg>
          </div>
        <% end %>
      <% else %>
        <% thumb_url =
          if(loaded_assoc?(@gallery_object, :video), do: Brando.Videos.Helpers.thumbnail_url(@gallery_object.video)) %>
        <%= if thumb_url do %>
          <img width="25" height="25" src={thumb_url} />
        <% else %>
          <div class="img-placeholder">
            <.icon name="hero-video-camera" />
          </div>
        <% end %>
      <% end %>
      <button
        type="button"
        class="delete-object"
        name={"#{@form_name}[drop_gallery_object_ids][]"}
        value={@gallery_object_field.index}
        data-sortable-filter
        phx-click={JS.dispatch("change")}
      >
        <.icon name="hero-x-mark" />
      </button>
    </div>
    """
  end

  @doc """
  Match a rendered form row back to the loaded object behind it.

  The form carries ids as strings; the object list holds them as integers, and
  a row for a not-yet-picked object carries `""` — which must not match a nil.
  """
  def find(%{gallery_objects: gallery_objects, gallery_object_field: field}) do
    image_id = field[:image_id].value
    video_id = field[:video_id].value

    Enum.find(gallery_objects, fn object ->
      same?(image_id, Map.get(object, :image_id)) or same?(video_id, Map.get(object, :video_id))
    end)
  end

  def media_id(field) do
    case field[:image_id].value do
      value when value in [nil, ""] -> field[:video_id].value
      value -> value
    end
  end

  defp same?(value, _other) when value in [nil, ""], do: false
  defp same?(_value, nil), do: false
  defp same?(value, other), do: to_string(value) == to_string(other)
end
