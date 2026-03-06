defmodule BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.Object do
  @moduledoc false
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  import Brando.Utils, only: [loaded_assoc?: 2]
  import Phoenix.HTML, only: [raw: 1]

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.GalleryBlock.OverrideForm
  alias Ecto.Changeset
  alias Phoenix.LiveView.JS

  # prop gallery_object_form, :any, required: true
  # prop gallery_objects, :list, required: true
  # prop display, :atom, required: true
  # prop myself, :any, required: true
  # prop uid, :string, required: true
  # prop gallery_form, :any, required: true
  # prop override_data, :map, required: true
  # prop block_data, :any, required: true
  # prop form_id, :string, required: true

  def render(assigns) do
    # Find the corresponding object for display - use index for new objects without IDs
    obj = Enum.at(assigns.gallery_objects, assigns.gallery_object_form.index)
    object_modal_id = "gallery-object-modal-#{assigns.uid}-#{assigns.gallery_object_form.index}"

    # Get the override info for this object to determine what values to display
    object_id_str =
      cond do
        obj && loaded_assoc?(obj, :image) -> to_string(obj.image.id)
        obj && loaded_assoc?(obj, :video) -> to_string(obj.video.id)
        true -> nil
      end

    # Get the current override form data from the block_data form
    current_override = get_current_override_from_form(assigns.block_data, object_id_str)

    # Determine the actual display values (considering current form overrides)
    display_values = compute_display_values_from_form(obj, current_override)

    assigns = assign(assigns, :obj, obj)
    assigns = assign(assigns, :object_modal_id, object_modal_id)
    assigns = assign(assigns, :display_values, display_values)

    ~H"""
    <div
      id={"gallery-object-#{@uid}-#{@gallery_object_form[:image_id].value || @gallery_object_form[:video_id].value}"}
      class="gallery-object preview sort-handle-gallery-object draggable"
      data-id={@gallery_object_form.index}
    >
      <!-- Hidden form fields -->
      <input type="hidden" name={@gallery_object_form[:id].name} value={@gallery_object_form[:id].value} />
      <input type="hidden" name={@gallery_object_form[:_persistent_id].name} value={@gallery_object_form.index} />
      <Input.input type={:hidden} field={@gallery_object_form[:gallery_id]} />
      <Input.input type={:hidden} field={@gallery_object_form[:image_id]} />
      <Input.input type={:hidden} field={@gallery_object_form[:video_id]} />
      <Input.input type={:hidden} field={@gallery_object_form[:creator_id]} />
      
    <!-- Hidden inputs for sorting -->
      <input
        type="hidden"
        name={"#{@gallery_form.name}[sort_gallery_object_ids][]"}
        value={@gallery_object_form.index}
      />
      
    <!-- Media type badge -->
      <div class="badge mini media-type-badge">
        <%= if @gallery_object_form[:image_id].value do %>
          <.icon name="hero-photo" />
        <% else %>
          <.icon name="hero-video-camera" />
        <% end %>
      </div>

      <%= if @gallery_object_form[:image_id].value do %>
        <%!-- Display image if available --%>
        <%= if @obj && loaded_assoc?(@obj, :image) do %>
          <Content.image image={@obj.image} size={(@display == :grid && :thumb) || :smallest} />
        <% end %>
      <% else %>
        <%!-- Display video thumbnail or placeholder --%>
        <%= if @obj && loaded_assoc?(@obj, :video) && @obj.video.thumbnail do %>
          <Content.image image={@obj.video.thumbnail} size={(@display == :grid && :thumb) || :smallest} />
        <% else %>
          <div class="video-placeholder">
            <.icon name="hero-video-camera" />
            <%= if @obj && loaded_assoc?(@obj, :video) do %>
              <span>{@obj.video.title || "Video"}</span>
            <% end %>
          </div>
        <% end %>
      <% end %>

      <button
        class="delete-x"
        type="button"
        name={"#{@gallery_form.name}[drop_gallery_object_ids][]"}
        value={@gallery_object_form.index}
        phx-click={JS.dispatch("change")}
        data-sortable-filter
      >
        <.icon name="hero-x-mark" />
        <div class="text">{gettext("Delete")}</div>
      </button>

      <button
        :if={@gallery_object_form[:image_id].value}
        class="edit-image-btn"
        type="button"
        phx-click={
          JS.push("open_image_editor",
            target: @myself,
            value: %{image_id: @gallery_object_form[:image_id].value}
          )
          |> toggle_drawer("#image-editor-drawer")
        }
        data-sortable-filter
      >
        <.icon name="hero-pencil-square" />
      </button>

      <figcaption phx-click={show_modal("##{@object_modal_id}")} data-sortable-filter>
        <div>
          <span>{gettext("Caption")}</span>
          {raw(@display_values.title || "{ #{gettext("No caption")} }")}
        </div>
        <div>
          <span>{gettext("Alt. text")}</span>
          {@display_values.alt || "{ #{gettext("No alt text")} }"}
        </div>
      </figcaption>
      
    <!-- Individual modal for this gallery object (inside the div) -->
      <Content.modal title={gettext("Edit captions")} id={@object_modal_id} data-sortable-filter>
        <div class="panels">
          <div class="panel">
            <figure>
              <%= if @obj && loaded_assoc?(@obj, :image) do %>
                <Content.image image={@obj.image} size={:smallest} />
              <% else %>
                <%= if @obj && loaded_assoc?(@obj, :video) && @obj.video.thumbnail do %>
                  <Content.image image={@obj.video.thumbnail} size={:smallest} />
                <% else %>
                  <div class="video-placeholder">
                    <.icon name="hero-video-camera" />
                  </div>
                <% end %>
              <% end %>
            </figure>
          </div>
          <div class="panel">
            <.gallery_caption_overrides
              obj={@obj}
              uid={@uid}
              override_data={@override_data}
              block_data={@block_data}
            />
          </div>
        </div>
      </Content.modal>
    </div>
    """
  end

  ## Private functions

  defp get_current_override_from_form(block_data_form, object_id_str) do
    # Get the current changeset from the form source
    changeset = block_data_form.source

    # Get the current gallery_object_overrides from the changeset
    overrides = Changeset.get_field(changeset, :gallery_object_overrides, [])

    # Find the override for this specific object
    Enum.find(overrides, fn override ->
      case override do
        %Changeset{} ->
          Changeset.get_field(override, :object_id) == object_id_str

        %{object_id: id} ->
          id == object_id_str

        _ ->
          false
      end
    end)
  end

  defp compute_display_values_from_form(nil, _), do: %{title: nil, alt: nil, credits: nil}

  defp compute_display_values_from_form(obj, nil) do
    # No override form, use base values
    cond do
      loaded_assoc?(obj, :image) ->
        %{
          title: obj.image.title,
          alt: obj.image.alt,
          credits: obj.image.credits
        }

      loaded_assoc?(obj, :video) ->
        %{
          title: obj.video.title,
          alt: nil,
          credits: nil
        }

      true ->
        %{title: nil, alt: nil, credits: nil}
    end
  end

  defp compute_display_values_from_form(obj, override) do
    # Get base values
    base_values =
      cond do
        loaded_assoc?(obj, :image) ->
          %{
            title: obj.image.title,
            alt: obj.image.alt,
            credits: obj.image.credits
          }

        loaded_assoc?(obj, :video) ->
          %{
            title: obj.video.title,
            alt: nil,
            credits: nil
          }

        true ->
          %{title: nil, alt: nil, credits: nil}
      end

    # Extract override values whether it's a changeset or struct
    {use_default_title, use_default_credits, use_default_alt, title, credits, alt} =
      case override do
        %Changeset{} ->
          {
            Changeset.get_field(override, :use_default_title),
            Changeset.get_field(override, :use_default_credits),
            Changeset.get_field(override, :use_default_alt),
            Changeset.get_field(override, :title),
            Changeset.get_field(override, :credits),
            Changeset.get_field(override, :alt)
          }

        %{} ->
          {
            Map.get(override, :use_default_title, true),
            Map.get(override, :use_default_credits, true),
            Map.get(override, :use_default_alt, true),
            Map.get(override, :title),
            Map.get(override, :credits),
            Map.get(override, :alt)
          }

        _ ->
          {true, true, true, nil, nil, nil}
      end

    # Apply overrides from the current values
    %{
      title:
        if(use_default_title,
          do: base_values.title,
          else: title || base_values.title
        ),
      alt:
        if(use_default_alt,
          do: base_values.alt,
          else: alt || base_values.alt
        ),
      credits:
        if(use_default_credits,
          do: base_values.credits,
          else: credits || base_values.credits
        )
    }
  end

  ## Function components

  attr :obj, :map, required: true
  attr :uid, :string, required: true
  attr :override_data, :map, required: true
  attr :block_data, :any, required: true

  def gallery_caption_overrides(assigns) do
    # Extract object ID and look up precomputed data
    object_id_str =
      cond do
        loaded_assoc?(assigns.obj, :image) -> to_string(assigns.obj.image.id)
        loaded_assoc?(assigns.obj, :video) -> to_string(assigns.obj.video.id)
        true -> nil
      end

    # Get the precomputed override info for this object
    override_info = Map.get(assigns.override_data, object_id_str)

    if override_info do
      assigns = assign(assigns, :override_info, override_info)
      assigns = assign(assigns, :object_id_str, object_id_str)

      ~H"""
      <div>
        {# With initialized overrides, we can always use standard inputs_for}
        <.inputs_for :let={override_form} field={@block_data[:gallery_object_overrides]}>
          <%= if override_form[:object_id].value == @object_id_str do %>
            <.live_component
              module={OverrideForm}
              id={"override-inline-#{@uid}-#{@object_id_str}"}
              form={override_form}
              override_info={@override_info}
              variant={:inline}
            />
          <% end %>
        </.inputs_for>
      </div>
      """
    else
      ~H"""
      <div>
        <p>{gettext("Caption overrides not available - no override data")}</p>
      </div>
      """
    end
  end
end
