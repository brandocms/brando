defmodule BrandoAdmin.Components.Form.FileDrawer do
  @moduledoc """
  Markup for the form's file drawer.

  **Markup only**, on the same measurement that produced `VideoDrawer`: the
  drawer's `update/2` and `handle_event/3` clauses stay in
  `BrandoAdmin.Components.Form` because they write the *parent's* state, and
  `assign_drawer_recovery_state/1` computes image, video and file state in a
  single `cond` that cannot be split three ways. Every input this module needs —
  `myself` included — is already an explicit assign at the call site, which is
  what makes the markup half free.

  The two JS command helpers come along because their only callers are in here.
  `close_file/2` dispatches a submit at `#file-drawer-form`, which is rendered
  by `render/1` — helper and markup are one unit and were only ever apart by
  accident of file layout.

  Follows `MetaDrawer`, `ScheduledPublishingDrawer` and `VideoDrawer`: a
  `:component` exposing `render/1`, whose events belong to the parent form.

  Note this does **not** reduce compile coupling, and no longer claims to. The
  admin's single compile cycle runs through `use BrandoAdmin, :component`, so
  every component is inside it regardless of who calls whom — measured when
  `Form.Primitives` was extracted and the cycle grew by one node.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias Phoenix.LiveView.JS

  # prop file_changeset, :any, required: true
  # prop myself, :any, required: true
  # prop edit_file, :map, required: true
  #
  # `myself` is the *parent* form's CID, not this module's — this is a function
  # component and has none. Every event the drawer emits routes back to `Form`,
  # which is where its `handle_event/3` clauses stayed.

  def render(assigns) do
    ~H"""
    <Content.drawer id="file-drawer" title={gettext("File details")} close={close_file(@myself)} z={1001} narrow light>
      <.form
        :let={file_form}
        :if={@file_changeset}
        id="file-drawer-form"
        for={@file_changeset}
        phx-submit="save_file"
        phx-change="validate_file"
        phx-target={@myself}
      >
        <div
          id="file-drawer-form-preview"
          phx-hook="Brando.UploadTrigger"
          data-kind="entry_field"
          data-asset-type="file"
          data-max-files="1"
          data-asset-id={@edit_file.file && @edit_file.file.id}
          data-field={@edit_file.field}
          data-path={Jason.encode!(@edit_file.path || [])}
          data-config-target={
            @edit_file.field &&
              Brando.Assets.ConfigTarget.serialize({"file", Map.get(@edit_file, :schema) || @schema, @edit_file.field})
          }
          class="file-drawer-preview"
        >
          <input id="file-drawer-upload-input" type="file" class="file-input" />
          <div
            id="file-drawer-upload-progress"
            class="media-field-progress"
            phx-update="ignore"
            role="status"
            aria-live="polite"
          >
          </div>

          <div class="img-placeholder">
            <div class="placeholder-wrapper">
              <div class="svg-wrapper">
                <.icon name="file-up" class="icon-add-file" />
              </div>
            </div>
          </div>

          <div
            :if={
              @edit_file && @edit_file[:file] &&
                !is_struct(@edit_file[:file], Ecto.Association.NotLoaded)
            }
            class="file-info"
          >
            <div class="filename">{@edit_file.file.filename}</div>
            <div class="mimetype">{@edit_file.file.mime_type}</div>
            <div class="filesize">
              {Brando.Utils.human_size(@edit_file.file.filesize)}
            </div>
          </div>
        </div>

        <div class="media-drawer-actions">
          <button
            class="media-button"
            type="button"
            phx-click={JS.dispatch("click", to: "#file-drawer-upload-input")}
          >
            {gettext("Upload")}
          </button>

          <button class="media-button" type="button" phx-click={toggle_drawer("#file-picker")}>
            {gettext("Select file")}
          </button>

          <button class="media-button" type="button" phx-click={reset_file_field(@myself)}>
            {gettext("Remove")}
          </button>
        </div>

        <div :if={@edit_file.file} class="brando-input">
          <Input.text field={file_form[:title]} label={gettext("Title")} />
        </div>
      </.form>
    </Content.drawer>
    """
  end

  def reset_file_field(js \\ %JS{}, target) do
    js
    |> JS.push("reset_file_field", target: target)
    |> JS.push("blur", target: target)
    |> toggle_drawer("#file-drawer")
  end

  # The blur releases the field for the other editors (`Form.focus_field/2`).
  def close_file(js \\ %JS{}, target) do
    js
    |> JS.dispatch("submit", to: "#file-drawer-form", detail: %{bubbles: true, cancelable: true})
    |> JS.push("blur", target: target)
    |> toggle_drawer("#file-drawer")
  end
end
