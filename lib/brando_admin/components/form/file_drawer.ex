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
  `close_file/1` dispatches a submit at `#file-drawer-form`, which is rendered
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
    <Content.drawer id="file-drawer" title={gettext("File")} close={close_file()} z={1001} narrow>
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
          data-field={@edit_file.field}
          data-path={Jason.encode!(@edit_file.path || [])}
          data-config-target={
            @edit_file.field &&
              Brando.Assets.ConfigTarget.serialize({"file", Map.get(@edit_file, :schema) || @schema, @edit_file.field})
          }
          class="file-drawer-preview"
        >
          <input id="file-drawer-upload-input" type="file" class="file-input" />

          <div class="img-placeholder">
            <div class="placeholder-wrapper">
              <div class="svg-wrapper">
                <svg class="icon-add-file" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M14.997 2L21 8l.001 4.26a5.471 5.471 0 0 0-2-1.053L19 9h-5V4H5v16h5.06a4.73 4.73 0 0 0 .817 2H3.993a.993.993 0 0 1-.986-.876L3 21.008V2.992c0-.498.387-.927.885-.985L4.002 2h10.995zM17.5 13a3.5 3.5 0 0 1 3.5 3.5l-.001.103a2.75 2.75 0 0 1-.581 5.392L20.25 22h-5.5l-.168-.005a2.75 2.75 0 0 1-.579-5.392L14 16.5a3.5 3.5 0 0 1 3.5-3.5zm0 2a1.5 1.5 0 0 0-1.473 1.215l-.02.14L16 16.5v1.62l-1.444.406a.75.75 0 0 0 .08 1.466l.109.008h5.51a.75.75 0 0 0 .19-1.474l-1.013-.283L19 18.12V16.5l-.007-.144A1.5 1.5 0 0 0 17.5 15z" />
                </svg>
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
            <div class="filename">&#x2B24; {@edit_file.file.filename}</div>
            <div class="mimetype">&#x2B24; {@edit_file.file.mime_type}</div>
            <div class="filesize">
              &#x2B24; {Brando.Utils.human_size(@edit_file.file.filesize)}
            </div>
          </div>
        </div>

        <div class="button-group vertical">
          <button
            class="secondary"
            type="button"
            phx-click={JS.dispatch("click", to: "#file-drawer-upload-input")}
          >
            {gettext("Upload file")}
          </button>

          <button class="secondary" type="button" phx-click={toggle_drawer("#file-picker")}>
            {gettext("Select existing file")}
          </button>

          <button class="secondary" type="button" phx-click={reset_file_field(@myself)}>
            {gettext("Reset file field")}
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
    |> toggle_drawer("#file-drawer")
  end

  def close_file(js \\ %JS{}) do
    js
    |> JS.dispatch("submit", to: "#file-drawer-form", detail: %{bubbles: true, cancelable: true})
    |> toggle_drawer("#file-drawer")
  end
end
