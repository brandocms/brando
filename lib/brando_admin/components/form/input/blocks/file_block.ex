defmodule BrandoAdmin.Components.Form.Input.Blocks.FileBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Assets.MediaField
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input
  alias Ecto.Changeset

  @override_fields [:title, :label, :description, :class, :target_blank, :download, :config_target]

  def update(%{event: "live_upload_complete", expected_asset_id: expected} = assigns, socket) do
    current_id = socket.assigns[:file] && socket.assigns.file.id

    if Brando.Uploads.AssetIntent.current_selection?(expected, current_id) do
      update(Map.delete(assigns, :expected_asset_id), socket)
    else
      {:ok, socket}
    end
  end

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
          config_open={@config_open}
          config_layout="editor"
          config_title={gettext("Configure file")}
          config_subtitle={@ref_description || gettext("Settings for this use of the file")}
          config_icon="hero-document"
        >
          <:description>
            {@ref_description || (@file && (@block_data.label || @block_data.title || @file.title || @file.filename)) ||
              gettext("No file selected")}
          </:description>

          <MediaField.field
            id={"block-#{@uid}-file-upload"}
            type={:file}
            asset={@file}
            kind="block_ref_file"
            component_id={"#{@uid}-file"}
            config_target={@block_data.config_target || "default"}
            label={@ref_description}
            presentation={:block}
            configure={JS.push("open_block_config", target: @target, value: %{uid: @uid})}
            browse={JS.push("set_target", target: @myself) |> toggle_drawer("#file-picker")}
            remove={JS.push("reset_file", target: @myself)}
          />

          <:config>
            <Content.modal_sections id={"file-#{@uid}-config-sections"}>
              <:section id="settings" label={gettext("Link & behavior")} icon="hero-link">
                <div class="media-section-heading">
                  <h3 class="modal-section-title">{gettext("Link & behavior")}</h3>
                  <p class="modal-muted">{gettext("These settings apply to this use of the file.")}</p>
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
              </:section>
              <:section id="file" label={gettext("File")} icon="hero-document">
                <div class="media-section-heading">
                  <h3 class="modal-section-title">{gettext("Selected file")}</h3>
                </div>
                <MediaField.field
                  id={"block-#{@uid}-file-modal-upload"}
                  type={:file}
                  asset={@file}
                  kind="block_ref_file"
                  component_id={"#{@uid}-file"}
                  config_target={@block_data.config_target || "default"}
                  browse={JS.push("set_target", target: @myself) |> toggle_drawer("#file-picker")}
                  remove={JS.push("reset_file", target: @myself)}
                />
              </:section>
            </Content.modal_sections>
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
    data = Block.current_block_data_map(socket.assigns.block, @override_fields)

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
