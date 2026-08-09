defmodule BrandoAdmin.Components.Form.ImageDrawer do
  @moduledoc """
  Markup for the form's image drawer and the image editor drawer it opens.

  **Markup only**, on the same measurement as `VideoDrawer` and `FileDrawer`.
  The audit plan expected this pair to be the *harder* extraction because the
  image drawer additionally owns `image_editor_*` state and a focal-point
  component. Checked before moving anything: that state is `Form`'s, not this
  module's — the editor's `handle_event/3` clauses, its `allow_upload` for
  `:image_editor_upload`, and the crop-group builders all read and write the
  parent's socket, and `assign_drawer_recovery_state/1` covers image, video and
  file in one `cond`. So the split lands in the same place: markup out,
  behaviour stays.

  `editor/1` (the image editor drawer) is here rather than in `Form` because
  `render/1` is its only opener and `close_image_editor/1` targets the element
  it renders.

  `upload_target_dom_id/1` came along too: it had exactly one caller, in
  `render/1`.

  Follows `MetaDrawer`, `ScheduledPublishingDrawer`, `VideoDrawer` and
  `FileDrawer`: a `:component` exposing `render/1`, whose events belong to the
  parent form.

  Note this does **not** reduce compile coupling, and no longer claims to. The
  admin's single compile cycle runs through `use BrandoAdmin, :component`, so
  every component is inside it regardless of who calls whom — measured when
  `Form.Primitives` was extracted and the cycle grew by one node.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Image.FocalPoint
  alias Phoenix.LiveView.JS

  # prop image_changeset, :any, required: true
  # prop myself, :any, required: true
  # prop schema, :atom, required: true
  # prop edit_image, :map, required: true
  # prop processing, :boolean, required: true
  #
  # `myself` is the *parent* form's CID, not this module's — this is a function
  # component and has none. Every event the drawer emits routes back to `Form`,
  # which is where its `handle_event/3` clauses stayed.
  #
  # `processing` IS consumed here, unlike the assign of the same name that was
  # dropped from the `VideoDrawer` call site — it gates the drawer's
  # processing state, so the call site keeps passing it.

  def render(assigns) do
    upload_dom_id = upload_target_dom_id(to_string(assigns.edit_image.field))

    assigns = assign(assigns, :upload_dom_id, upload_dom_id)

    ~H"""
    <Content.drawer id="image-drawer" title={gettext("Image")} close={close_image()} z={1001} narrow>
      <.form
        :let={image_form}
        :if={@image_changeset}
        id="image-drawer-form"
        for={@image_changeset}
        phx-submit="save_image"
        phx-change="validate_image"
        phx-target={@myself}
      >
        <%!-- `data-click-mode="trigger"` because this wrapper contains the
        focal-point picker, which is what that mode exists for. Under the
        default mode UploadTrigger opens the file chooser on any click that is
        not a button or a link, and the focal point is a plain `div` — so
        setting a focal point also popped up an upload dialog. Only
        `.upload-trigger` opens it now: the empty-state placeholder below, plus
        the "Upload image" button, which dispatches straight to the input and
        never went through the hook. Drag and drop is unaffected. --%>
        <div
          id="image-drawer-form-preview"
          phx-hook="Brando.UploadTrigger"
          data-kind="entry_field"
          data-asset-type="image"
          data-field={@edit_image.field}
          data-path={Jason.encode!(@edit_image.path || [])}
          data-config-target={
            @edit_image.field &&
              Brando.Assets.ConfigTarget.serialize({"image", Map.get(@edit_image, :schema) || @schema, @edit_image.field})
          }
          data-folder-browser="true"
          data-accept=".jpg,.jpeg,.png,.gif,.webp,.svg"
          data-click-mode="trigger"
          class="image-drawer-preview"
        >
          <input id="image-drawer-upload-input" type="file" class="file-input" />
          <%= if @edit_image.image do %>
            <figure class="grid-overlay">
              <div class="drop-indicator">
                <div>{gettext("+ Drop here to upload")}</div>
              </div>
              <.live_component
                module={FocalPoint}
                id={"image-drawer-focal-#{@upload_dom_id}"}
                image={@edit_image}
                form_id={image_form.id}
                form_name={image_form.name}
              />
              <img
                width={@edit_image.image.width}
                height={@edit_image.image.height}
                src={Brando.Utils.img_url(@edit_image.image, :original, prefix: Brando.Utils.media_url())}
              />
            </figure>
            <figcaption class="tiny">{@edit_image.image.path}</figcaption>
          <% else %>
            <%!-- Carries `upload-trigger` so the empty state stays click-to-upload
            under `trigger` mode — there is no focal point to conflict with when
            there is no image. --%>
            <div class="img-placeholder upload-trigger">
              <div class="placeholder-wrapper">
                <div class="svg-wrapper">
                  <svg class="icon-add-image" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                    <path d="M0,0H24V24H0Z" transform="translate(0 0)" fill="none" />
                    <polygon
                      class="plus"
                      points="21 15 21 18 24 18 24 20 21 20 21 23 19 23 19 20 16 20 16 18 19 18 19 15 21 15"
                    />
                    <path
                      d="M21,3a1,1,0,0,1,1,1v9H20V5H4V19L14,9l3,3v2.83l-3-3L6.83,19H14v2H3a1,1,0,0,1-1-1V4A1,1,0,0,1,3,3Z"
                      transform="translate(0 0)"
                    />
                    <circle cx="8" cy="9" r="2" />
                  </svg>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <div class="button-group vertical">
          <button
            id={"image-drawer-upload-#{@upload_dom_id}"}
            class="secondary"
            type="button"
            phx-click={JS.dispatch("click", to: "#image-drawer-upload-input")}
          >
            {gettext("Upload image")}
          </button>
          <button class="secondary" type="button" phx-click={toggle_drawer("#image-picker")}>
            {gettext("Select existing image")}
          </button>

          <button
            :if={@edit_image.image && @edit_image.image.path}
            class="secondary"
            type="button"
            phx-click={open_image_editor(@edit_image, @myself)}
          >
            {gettext("Edit/Crop image")}
          </button>

          <button
            :if={@edit_image.image}
            class="secondary"
            type="button"
            phx-click={duplicate_image(@edit_image, @myself)}
          >
            {gettext("Duplicate image")}
          </button>

          <button class="secondary" type="button" phx-click={reset_image_field(@myself)}>
            {gettext("Reset image field")}
          </button>
        </div>
        <%= if @edit_image.image do %>
          <div class="brando-input">
            <Input.text field={image_form[:title]} label={gettext("Caption")} />
          </div>

          <div class="brando-input">
            <Input.text field={image_form[:credits]} label={gettext("Credits")} />
          </div>

          <div class="brando-input">
            <Input.text field={image_form[:alt]} label={gettext("Alt. text")} />
          </div>
        <% end %>
      </.form>
    </Content.drawer>
    """
  end

  def editor(assigns) do
    ~H"""
    <Content.drawer
      id="image-editor-drawer"
      title={gettext("Image Editor")}
      close={close_image_editor()}
      z={1002}
      wide
    >
      <div
        id="image-editor-hook"
        phx-hook="Brando.ImageEditor"
        phx-update="ignore"
        data-label-crop-previews={gettext("Crop previews")}
      >
        <div class="image-editor">
          <div class="image-editor-main">
            <canvas id="image-editor-canvas"></canvas>
            <canvas id="image-editor-overlay"></canvas>
            <div class="image-editor-focal-pin"></div>
          </div>
          <div class="image-editor-sidebar">
            <div class="image-editor-controls">
              <div class="zoom-header">
                <label>{gettext("Zoom")}</label>
                <span class="zoom-value" id="image-editor-zoom-value">1.00x</span>
              </div>
              <input type="range" id="image-editor-zoom" min="1" max="3" step="0.05" value="1" />
              <button type="button" id="image-editor-reset">{gettext("Reset")}</button>
            </div>
            <div class="image-editor-previews" id="image-editor-previews"></div>
          </div>
          <div class="image-editor-actions">
            <button type="button" class="secondary" phx-click={close_image_editor()}>
              {gettext("Cancel")}
            </button>
            <button type="button" class="secondary" id="image-editor-save-replace">
              {gettext("Save changes")}
            </button>
            <button type="button" class="primary" id="image-editor-save-new">
              {gettext("Save as new copy")}
            </button>
          </div>
        </div>
      </div>
    </Content.drawer>
    """
  end

  def open_image_editor(js \\ %JS{}, edit_image, target) do
    js
    |> JS.push("open_image_editor", value: %{image_id: edit_image.image.id}, target: target)
    |> toggle_drawer("#image-editor-drawer")
  end

  def close_image_editor(js \\ %JS{}) do
    toggle_drawer(js, "#image-editor-drawer")
  end

  def duplicate_image(js \\ %JS{}, edit_image, target) do
    JS.push(js, "duplicate_image", value: %{image_id: edit_image.image.id}, target: target)
  end

  def reset_image_field(js \\ %JS{}, target) do
    js
    |> JS.push("reset_image_field", target: target)
    |> toggle_drawer("#image-drawer")
  end

  def close_image(js \\ %JS{}) do
    js
    |> JS.dispatch("submit", to: "#image-drawer-form", detail: %{bubbles: true, cancelable: true})
    |> toggle_drawer("#image-drawer")
  end

  defp upload_target_dom_id(value) when is_atom(value),
    do: value |> Atom.to_string() |> upload_target_dom_id()

  defp upload_target_dom_id(value) when is_binary(value) do
    value
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
    |> String.trim("-")
    |> case do
      "" -> "image"
      sanitized -> sanitized
    end
  end

  defp upload_target_dom_id(_), do: "image"
end
