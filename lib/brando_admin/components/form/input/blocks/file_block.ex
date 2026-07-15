defmodule BrandoAdmin.Components.Form.Input.Blocks.FileBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Villain.Blocks.FileBlock
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias Ecto.Changeset

  @override_fields [:title, :label, :description, :class, :target_blank, :download, :config_target]

  def update(%{event: "live_upload_complete", file: file}, socket) do
    socket
    |> commit_file(file)
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    block_data_cs = Block.get_block_data_changeset(assigns.block)
    block_data = Changeset.apply_changes(block_data_cs)
    uid = assigns.ref_form[:uid].value

    file =
      Block.resolve_ref_association(assigns[:ref_form], :file, :file_id, &Brando.Files.get_file/1)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, uid)
     |> assign(:block_data, block_data)
     |> assign(:file, file)}
  end

  def render(assigns) do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} class="file-block">
      <.inputs_for :let={block_data} field={@block[:data]}>
        <Block.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          multi={false}
          target={@target}
          ref_form={@ref_form}
        >
          <:description>
            {@ref_description || (@file && (@block_data.label || @block_data.title || @file.title || @file.filename)) ||
              gettext("No file selected")}
          </:description>

          <button
            :if={@file}
            type="button"
            class="file-card"
            phx-click={show_modal("#block-#{@uid}_config")}
          >
            <.icon name="hero-document" />
            <span class="file-card__meta">
              <span class="file-card__name">{@block_data.label || @block_data.title || @file.title || @file.filename}</span>
              <span class="file-card__sub">
                {@file.mime_type} · {Brando.Utils.human_size(@file.filesize)}
              </span>
            </span>
          </button>

          <div :if={!@file} class="upload-canvas empty">
            <.icon name="hero-document-plus" />
            <div class="instructions">
              <button
                type="button"
                class="primary small"
                phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#file-picker")}
              >
                {gettext("Browse files")}
              </button>
              <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}>
                {gettext("Upload a new file")}
              </button>
            </div>
          </div>

          <:config>
            <div class="panels">
              <div class="panel">
                <%= if @file do %>
                  <a class="file-card" href={Brando.Utils.file_url(@file)} target="_blank" rel="noopener">
                    <.icon name="hero-document" />
                    <span class="file-card__meta">
                      <span class="file-card__name">{@file.filename}</span>
                      <span class="file-card__sub">
                        {@file.mime_type} · {Brando.Utils.human_size(@file.filesize)}
                      </span>
                    </span>
                  </a>
                <% else %>
                  <div
                    id={"block-#{@uid}-file-upload"}
                    phx-hook="Brando.UploadTrigger"
                    data-kind="block_ref_file"
                    data-component-id={"#{@uid}-file"}
                    data-asset-type="file"
                    data-config-target={@block_data.config_target || "default"}
                    class="img-placeholder empty upload-canvas"
                  >
                    <input type="file" class="file-input" />
                    <.icon name="hero-document-plus" />
                    <div class="instructions">{gettext("Click or drop a file to upload")}</div>
                  </div>
                <% end %>
              </div>

              <div class="panel">
                <div class="button-group-vertical">
                  <button
                    type="button"
                    class="secondary"
                    phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#file-picker")}
                  >
                    {if @file, do: gettext("Replace file"), else: gettext("Select file")}
                  </button>
                  <button
                    :if={@file}
                    type="button"
                    class="danger"
                    phx-click={JS.push("reset_file", target: @myself)}
                  >
                    {gettext("Remove file")}
                  </button>
                </div>

                <Input.override_text
                  field={block_data[:title]}
                  label={gettext("Title")}
                  default_value={@file && @file.title}
                  target={@myself}
                />
                <Input.override_text
                  field={block_data[:label]}
                  label={gettext("Link label")}
                  default_value={@file && (@file.title || @file.filename)}
                  target={@myself}
                />
                <Input.textarea field={block_data[:description]} label={gettext("Description")} />
                <Input.text field={block_data[:class]} label={gettext("CSS class(es)")} />
                <Input.toggle field={block_data[:target_blank]} label={gettext("Open in new window/tab")} />
                <Input.toggle field={block_data[:download]} label={gettext("Download instead of open")} />
                <Input.input type={:hidden} field={block_data[:config_target]} />
              </div>
            </div>
          </:config>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("set_target", _, socket) do
    send_update(BrandoAdmin.Components.FilePicker,
      id: "file-picker",
      config_target: socket.assigns.block_data.config_target || "default",
      event_target: socket.assigns.myself,
      multi: false,
      selected_files: if(socket.assigns.file, do: [socket.assigns.file.id], else: [])
    )

    {:noreply, socket}
  end

  def handle_event("select_file", %{"id" => file_id}, socket) do
    case Brando.Files.get_file(file_id) do
      {:ok, file} -> socket |> commit_file(file) |> then(&{:noreply, &1})
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reset_file", _, socket) do
    data = %FileBlock.Data{} |> Map.from_struct() |> Map.take(@override_fields)

    socket
    |> Block.commit_ref_data(ref_data: data, file_id: nil, force_render: true)
    |> assign(:file, nil)
    |> then(&{:noreply, &1})
  end

  def handle_event("focus", _, socket), do: {:noreply, socket}

  defp commit_file(socket, file) do
    socket
    |> Block.commit_ref_data(
      ref_data: Block.current_block_data_map(socket.assigns.block, @override_fields),
      file_id: file.id,
      force_render: true
    )
    |> assign(:file, file)
  end
end
