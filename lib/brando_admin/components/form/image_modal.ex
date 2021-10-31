defmodule BrandoAdmin.Components.Form.ImageModal do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Subform

  import Brando.Gettext

  prop edit_image_id, :any
  prop edit_image_field, :list

  # def render(assigns) do
  #   ~F"""
  #   <div class="image-modal">
  #     <Modal title="Edit image" center_header={true} id={"edit-image-#{@form.id}-#{@field}-modal"}>
  #       <div
  #         id={"image-modal-dropzone"}"}
  #         class={"image-modal-content", ac: !@image}
  #         phx-hook="Brando.DragDrop">
  #         <div
  #           class="drop-target"
  #           phx-drop-target={"#{@upload_field.ref}"}>
  #           <div class="drop-indicator">
  #             <div>Drop here to upload</div>
  #           </div>
  #           <div class="image-modal-content-preview">
  #             <div
  #               :if={!Enum.empty?(@upload_field.entries)}
  #               class="input-image-previews">
  #               <article
  #                 :for={entry <- @upload_field.entries}
  #                 class="upload-entry">
  #                 {#if entry.progress && !entry.done?}
  #                   <div class="upload-status">
  #                     <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="12" height="12"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 2a1 1 0 0 1 1 1v3a1 1 0 0 1-2 0V3a1 1 0 0 1 1-1zm0 15a1 1 0 0 1 1 1v3a1 1 0 0 1-2 0v-3a1 1 0 0 1 1-1zm10-5a1 1 0 0 1-1 1h-3a1 1 0 0 1 0-2h3a1 1 0 0 1 1 1zM7 12a1 1 0 0 1-1 1H3a1 1 0 0 1 0-2h3a1 1 0 0 1 1 1zm12.071 7.071a1 1 0 0 1-1.414 0l-2.121-2.121a1 1 0 0 1 1.414-1.414l2.121 2.12a1 1 0 0 1 0 1.415zM8.464 8.464a1 1 0 0 1-1.414 0L4.93 6.344a1 1 0 0 1 1.414-1.415L8.464 7.05a1 1 0 0 1 0 1.414zM4.93 19.071a1 1 0 0 1 0-1.414l2.121-2.121a1 1 0 1 1 1.414 1.414l-2.12 2.121a1 1 0 0 1-1.415 0zM15.536 8.464a1 1 0 0 1 0-1.414l2.12-2.121a1 1 0 0 1 1.415 1.414L16.95 8.464a1 1 0 0 1-1.414 0z"/></svg> Uploading image...
  #                   </div>
  #                 {/if}
  #                 <figure>
  #                   {live_img_preview entry}
  #                 </figure>
  #                 <p
  #                   :for={err <- upload_errors(@upload_field, entry)}
  #                   class="alert alert-danger">{Brando.Upload.error_to_string(err)}</p>
  #               </article>
  #             </div>
  #             {#if @image && @image.path && Enum.empty?(@upload_field.entries)}
  #               <figure>
  #                 <FocalPoint
  #                   id={"#{@form.id}-#{@field}-focal"}
  #                   form={@form}
  #                   field_name={@field}
  #                   focal={@focal} />
  #                 <img
  #                   width={"#{@image.width}"}
  #                   height={"#{@image.height}"}
  #                   src={"#{Utils.img_url(@image, :original, prefix: Utils.media_url())}"} />
  #               </figure>
  #             {/if}
  #             {#if !@image && Enum.empty?(@upload_field.entries)}
  #               <div class="img-placeholder">
  #                 <div class="placeholder-wrapper">
  #                   <div class="svg-wrapper">
  #                     <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>
  #                   </div>
  #                 </div>
  #               </div>
  #               {!--
  #               <div class="upload-file-size-instructions">
  #                 <p>
  #                   <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM11 7h2v2h-2V7zm0 4h2v6h-2v-6z"/></svg>
  #                   Max allowed size for the field is 3MB.
  #                 </p>
  #                 <p>If your image is larger than the limit, try compressing the file with an online service like <a href="https://squoosh.app/" target="_blank" rel="noopener nofollow">squoosh.app</a> or a mac desktop app like <a href="https://imageoptim.com/mac/" target="_blank" rel="noopener nofollow">ImageOptim</a></p>
  #               </div>
  #               --}
  #             {/if}
  #             {#if @image && @image.path && Enum.empty?(@upload_field.entries)}
  #               <div class="info">
  #                 Path: {@image.path}<br>
  #                 Dimensions: {@image.width}&times;{@image.height}
  #               </div>
  #             {/if}
  #           </div>

  #           <div class="image-modal-content-info">
  #             {#if @image}
  #               {text_input @form, @relation_field}
  #               <Inputs
  #                 :let={form: sf}
  #                 form={@form}
  #                 for={@field}>
  #                 <div class="field-wrapper">
  #                   <div class="label-wrapper">
  #                     <label class="control-label"><span>Caption/Title</span></label>
  #                   </div>
  #                   <div class="field-base">
  #                     {text_input sf, :title, class: "text", phx_debounce: 750}
  #                   </div>
  #                 </div>
  #                 <div class="field-wrapper">
  #                   <div class="label-wrapper">
  #                     <label class="control-label"><span>Alt text (for accessibility)</span></label>
  #                   </div>
  #                   <div class="field-base">
  #                     {text_input sf, :alt, class: "text", phx_debounce: 750}
  #                   </div>
  #                 </div>
  #                 <div class="field-wrapper">
  #                   <div class="label-wrapper">
  #                     <label class="control-label"><span>Credits</span></label>
  #                   </div>
  #                   <div class="field-base">
  #                     {text_input sf, :credits, class: "text", phx_debounce: 750}
  #                   </div>
  #                 </div>

  #                 <MapInputs
  #                   :let={value: value, name: name}
  #                   form={sf}
  #                   for={:sizes}>
  #                   <input type="hidden" name={"#{name}"} value={"#{value}"} />
  #                 </MapInputs>

  #                 <ArrayInputs
  #                   :let={value: array_value, name: array_name}
  #                   form={sf}
  #                   for={:formats}>
  #                   <input type="hidden" name={array_name} value={array_value} />
  #                 </ArrayInputs>

  #                 <div class="file-input-wrapper">
  #                   <span class="label">
  #                     Pick a file
  #                   </span>
  #                   {live_file_input Map.get(@uploads, @field)}
  #                 </div>
  #                 <button
  #                   class="secondary fw"
  #                   type="button"
  #                   :on-click="reset_field">Reset field</button>
  #               </Inputs>
  #             {#else}

  #               <div class="drop-instructions">
  #                 &larr; Drop image to upload or
  #               </div>
  #               <div class="file-input-wrapper">
  #                 <span class="label">
  #                   Pick a file
  #                 </span>
  #                 {live_file_input Map.get(@uploads, @field)}
  #               </div>
  #             {/if}
  #           </div>
  #         </div>
  #       </div>
  #     </Modal>
  #   </div>
  #   """
  # end
end
