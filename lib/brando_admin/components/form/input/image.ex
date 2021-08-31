defmodule BrandoAdmin.Components.Form.Input.Image do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Ecto.Changeset

  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Input.Image.FocalPoint
  alias BrandoAdmin.Components.Form.MapInputs
  alias Brando.Images
  alias Brando.Utils

  alias Surface.Components.Form.Inputs
  alias Surface.Components.Form.Input.InputContext
  alias Surface.Components.Form.TextInput
  alias Surface.Components.Form.HiddenInput

  prop form, :form
  prop blueprint, :any
  prop uploads, :any
  prop field, :atom
  prop input, :any

  data show_edit_meta, :boolean, default: false
  data focal, :any
  data image, :any
  data class, :any
  data file_name, :any
  data field_name, :any

  def update(%{field: field} = assigns, socket) do
    image = get_field(assigns.form.source, field)

    focal =
      if is_map(image) && image.path,
        do: Map.get(image, :focal, %Images.Focal{}),
        else: nil

    file_name = if is_map(image) && image.path, do: Path.basename(image.path), else: nil

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:image, image)
     |> assign(:file_name, file_name)
     |> assign(:field_name, field)
     |> assign(:class, "small")
     |> assign_new(:upload_field, fn ->
       assigns.uploads[field]
     end)
     |> assign(:focal, focal)}
  end

  def update(%{input: input} = assigns, socket) do
    image = get_field(assigns.form.source, input.name)

    focal =
      if is_map(image) && image.path,
        do: Map.get(image, :focal, %Images.Focal{}),
        else: nil

    file_name = if is_map(image) && image.path, do: Path.basename(image.path), else: nil

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:image, image)
     |> assign(:file_name, file_name)
     |> assign(:field_name, assigns.input.name)
     |> assign(:class, assigns.input.opts[:class])
     |> assign_new(:upload_field, fn ->
       assigns.uploads[assigns.input.name]
     end)
     |> assign(:focal, focal)}
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={@field_name}
      class={@class}
      form={@form}>
      <div>
        <div class="input-image">
          <div class="image-wrapper-compact">
            {#if @image && @image.path}
              {!-- We have an image with a path. --}
              {#if @image.sizes["thumb"]}
                <img
                  width="25"
                  height="25"
                  src={"#{Utils.img_url(@image, :thumb, prefix: Utils.media_url())}"} />
              {#else}
                {!-- We have a path, but no thumb size. Image is processing --}
                <div class="img-placeholder">
                  <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z"/></svg>
                </div>
              {/if}

              <div class="image-info">
                {@file_name} — {@image.width}&times;{@image.height}
                {#if @image.title}
                  <div class="title">Caption: {@image.title}</div>
                {/if}
                <button
                  class="btn-small"
                  type="button"
                  :on-click="show_meta_edit_modal"
                  phx-value-id={"edit-image-#{@form.id}-#{@field_name}-modal"}>Edit image</button>
              </div>
            {#else}
              <input type="hidden" name={"#{@form.name}[#{@field_name}]"} value="" />

              <div class="img-placeholder">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>
              </div>
              <div class="image-info">
                No image associated with field
                <button
                  class="btn-small"
                  type="button"
                  :on-click="show_meta_edit_modal"
                  phx-value-id={"edit-image-#{@form.id}-#{@field_name}-modal"}>Add image</button>
              </div>
            {/if}
          </div>
          <div class="image-meta">
            <Modal title="Edit image" center_header={true} id={"edit-image-#{@form.id}-#{@field_name}-modal"}>
              <div
                id={"#{"#{@blueprint.naming.id}-#{@field_name}-dropzone"}"}
                class={"image-modal-content", ac: !@image}
                phx-hook="Brando.DragDrop">
                <div
                  class="drop-target"
                  phx-drop-target={"#{@upload_field.ref}"}>
                  <div class="drop-indicator">
                    <div>Drop here to upload</div>
                  </div>
                  <div class="image-modal-content-preview">
                    <div
                      :if={!Enum.empty?(@upload_field.entries)}
                      class="input-image-previews">
                      <article
                        :for={entry <- @upload_field.entries}
                        class="upload-entry">
                        {#if entry.progress && !entry.done?}
                          <div class="upload-status">
                            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 2a1 1 0 0 1 1 1v3a1 1 0 0 1-2 0V3a1 1 0 0 1 1-1zm0 15a1 1 0 0 1 1 1v3a1 1 0 0 1-2 0v-3a1 1 0 0 1 1-1zm10-5a1 1 0 0 1-1 1h-3a1 1 0 0 1 0-2h3a1 1 0 0 1 1 1zM7 12a1 1 0 0 1-1 1H3a1 1 0 0 1 0-2h3a1 1 0 0 1 1 1zm12.071 7.071a1 1 0 0 1-1.414 0l-2.121-2.121a1 1 0 0 1 1.414-1.414l2.121 2.12a1 1 0 0 1 0 1.415zM8.464 8.464a1 1 0 0 1-1.414 0L4.93 6.344a1 1 0 0 1 1.414-1.415L8.464 7.05a1 1 0 0 1 0 1.414zM4.93 19.071a1 1 0 0 1 0-1.414l2.121-2.121a1 1 0 1 1 1.414 1.414l-2.12 2.121a1 1 0 0 1-1.415 0zM15.536 8.464a1 1 0 0 1 0-1.414l2.12-2.121a1 1 0 0 1 1.415 1.414L16.95 8.464a1 1 0 0 1-1.414 0z"/></svg> Uploading image...
                          </div>
                        {/if}
                        <figure>
                          {live_img_preview entry}
                        </figure>
                        {!--
                        <button phx-click="cancel-upload" phx-value-ref={"#{entry.ref}"} aria-label="cancel">&times;</button>
                        --}
                        <p
                          :for={err <- upload_errors(@upload_field, entry)}
                          class="alert alert-danger">{Phoenix.LiveView.Helpers.error_to_string(err)}</p>
                      </article>
                    </div>
                    {!--
                    <FocalPoint
                      field_name={@field_name}
                      focal={@focal} />
                    --}
                    {#if @image && @image.path && Enum.empty?(@upload_field.entries)}
                      <img
                        width={"#{@image.width}"}
                        height={"#{@image.height}"}
                        src={"#{Utils.img_url(@image, :original, prefix: Utils.media_url())}"} />
                    {/if}
                    {#if !@image && Enum.empty?(@upload_field.entries)}
                      <div class="img-placeholder">
                        <div class="placeholder-wrapper">
                          <div class="svg-wrapper">
                            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>
                          </div>
                        </div>
                      </div>
                      {!--
                      <div class="upload-file-size-instructions">
                        <p>
                          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM11 7h2v2h-2V7zm0 4h2v6h-2v-6z"/></svg>
                          Max allowed size for the field is 3MB.
                        </p>
                        <p>If your image is larger than the limit, try compressing the file with an online service like <a href="https://squoosh.app/" target="_blank" rel="noopener nofollow">squoosh.app</a> or a mac desktop app like <a href="https://imageoptim.com/mac/" target="_blank" rel="noopener nofollow">ImageOptim</a></p>
                      </div>
                      --}
                    {/if}
                    {#if @image && @image.path && Enum.empty?(@upload_field.entries)}
                      <div class="info">
                        Path: {@image.path}<br>
                        Dimensions: {@image.width}&times;{@image.height}<br>
                        {@image.marked_as_deleted}
                      </div>
                    {/if}
                  </div>

                  <div class="image-modal-content-info">
                    {#if @image}
                      <Inputs
                        :let={form: sf}
                        form={@form}
                        for={@field_name}>
                        <div class="field-wrapper">
                          <div class="label-wrapper">
                            <label class="control-label"><span>Caption/Title</span></label>
                          </div>
                          <div class="field-base">
                            <TextInput class="text" form={sf} field={:title} />
                          </div>
                        </div>
                        <div class="field-wrapper">
                          <div class="label-wrapper">
                            <label class="control-label"><span>Alt text (for accessibility)</span></label>
                          </div>
                          <div class="field-base">
                            <TextInput class="text" form={sf} field={:alt} />
                          </div>
                        </div>
                        <div class="field-wrapper">
                          <div class="label-wrapper">
                            <label class="control-label"><span>Credits</span></label>
                          </div>
                          <div class="field-base">
                            <TextInput class="text" form={sf} field={:credits} />
                          </div>
                        </div>

                        <HiddenInput form={sf} field={:cdn} />
                        <HiddenInput form={sf} field={:dominant_color} />
                        <HiddenInput form={sf} field={:height} />
                        <HiddenInput form={sf} field={:path} />
                        <HiddenInput form={sf} field={:webp} />
                        <HiddenInput form={sf} field={:width} />
                        <HiddenInput form={sf} field={:marked_as_deleted} />

                        <Inputs
                          form={sf}
                          for={:focal}>
                          <HiddenInput field={:x} />
                          <HiddenInput field={:y} />
                        </Inputs>

                        <MapInputs
                          :let={value: value, name: name}
                          form={sf}
                          for={:sizes}>
                          <input type="hidden" name={"#{name}"} value={"#{value}"} />
                        </MapInputs>

                        <div class="file-input-wrapper">
                          <span class="label">
                            Pick a file
                          </span>
                          {live_file_input Map.get(@uploads, @field_name)}
                        </div>
                        <button
                          class="secondary fw"
                          type="button"
                          :on-click="reset_field">Reset field</button>
                      </Inputs>
                    {#else}

                      <div class="drop-instructions">
                        &larr; Drop image to upload or
                      </div>
                      <div class="file-input-wrapper">
                        <span class="label">
                          Pick a file
                        </span>
                        {live_file_input Map.get(@uploads, @field_name)}
                      </div>
                    {/if}
                  </div>
                </div>
              </div>
            </Modal>
          </div>
        </div>
      </div>
    </FieldBase>
    """
  end

  def handle_event("show_meta_edit_modal", %{"id" => id}, socket) do
    Modal.show(id)
    {:noreply, socket}
  end

  def handle_event("reset_field", _, socket) do
    field_name = socket.assigns.field_name
    changeset = socket.assigns.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    require Logger
    Logger.error("==> reset_field")

    updated_changeset =
      Ecto.Changeset.put_embed(
        changeset,
        field_name,
        nil
      )

    require Logger
    Logger.error("==> updated_changeset: #{inspect(updated_changeset, pretty: true)}")

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
    #  |> assign(:image, %{socket.assigns.image | marked_as_deleted: true})
    #  |> push_event("b:validate", %{})}
  end
end
