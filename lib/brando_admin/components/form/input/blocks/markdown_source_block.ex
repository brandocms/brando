defmodule BrandoAdmin.Components.Form.Input.Blocks.MarkdownSourceBlock do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  alias Brando.MarkdownSources
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.Input

  def mount(socket), do: {:ok, assign(socket, preview: nil, error: nil)}

  def update(assigns, socket) do
    data = assigns.block |> Block.get_block_data_changeset() |> Ecto.Changeset.apply_changes()
    source = MarkdownSources.get_source(data.source_id)
    previous = socket.assigns[:data]
    socket = if previous && previous.source_id != data.source_id, do: assign(socket, preview: nil), else: socket

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, assigns.ref_form[:uid].value)
     |> assign(:data, data)
     |> assign(:source, source)
     |> assign(:sources, MarkdownSources.list_sources())
     |> assign(:versions, if(source, do: MarkdownSources.versions(source.id), else: []))
     |> assign(:active_version, MarkdownSources.resolved_version(data))}
  end

  def render(assigns) do
    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={fields} field={@block[:data]}>
        <Block.block
          id={"block-#{@uid}-base"}
          block={@block}
          is_ref?={true}
          multi={false}
          target={@target}
          ref_form={@ref_form}
          config_open={@config_open}
        >
          <:description>{if @source, do: @source.name, else: gettext("Markdown source")}</:description>
          <div class="markdown-source-editor">
            <label for={fields[:source_id].id}>{gettext("Source")}</label>
            <select id={fields[:source_id].id} name={fields[:source_id].name}>
              <option value="">{gettext("Choose a Markdown source")}</option>
              <option :for={source <- @sources} value={source.id} selected={source.id == @data.source_id}>
                {source.name}
              </option>
            </select>
            <label for={fields[:policy].id}>{gettext("Update policy")}</label>
            <select id={fields[:policy].id} name={fields[:policy].name}>
              <option value="review" selected={@data.policy == :review}>{gettext("Review updates")}</option>
              <option value="follow" selected={@data.policy == :follow}>{gettext("Follow updates automatically")}</option>
              <option value="pinned" selected={@data.policy == :pinned}>{gettext("Pin a version")}</option>
            </select>
            <Input.input type={:hidden} field={fields[:version_id]} />
            <p :if={@data.policy == :follow} class="markdown-source-note">
              {gettext(
                "Repository updates will change this placement automatically after you save the entry. Restored revisions also follow the current source."
              )}
            </p>
            <dl :if={@source} class="markdown-source-meta">
              <div>
                <dt>{gettext("File")}</dt><dd>{@source.path}</dd>
              </div>
              <div>
                <dt>{gettext("Branch")}</dt><dd>{@source.ref}</dd>
              </div>
              <div>
                <dt>{gettext("Active commit")}</dt><dd>
                  {if @active_version, do: String.slice(@active_version.commit, 0, 12), else: gettext("No version selected")}
                </dd>
              </div>
            </dl>
            <p
              :if={@source && @data.policy == :review && @source.latest_version_id != @data.version_id}
              class="markdown-source-note"
            >
              {gettext("An update is available for review. Preview a commit and use the displayed version to accept it.")}
            </p>
            <p :if={@source && @source.last_error} role="status">{@source.last_error}</p>
            <div :if={@source} class="markdown-source-actions">
              <button type="button" class="markdown-source-button" phx-click="refresh_versions" phx-target={@myself}>{gettext(
                "Check available versions"
              )}</button>
              <a href="/admin/config/markdown-sources" target="_blank" rel="noopener">{gettext("Manage sources")}</a>
            </div>
            <div :if={@versions != []} class="markdown-source-review">
              <label for={"markdown-preview-#{@uid}"}>{gettext("Preview a version")}</label>
              <select
                id={"markdown-preview-#{@uid}"}
                name="markdown_preview_version"
                phx-change="preview"
                phx-target={@myself}
              >
                <option value="">{gettext("Choose a commit to preview")}</option>
                <option :for={version <- @versions} value={version.id} selected={@preview && @preview.id == version.id}>
                  {String.slice(version.commit, 0, 12)} · {Calendar.strftime(version.inserted_at, "%Y-%m-%d %H:%M UTC")}
                </option>
              </select>
              <section :if={@preview} aria-label={gettext("Markdown preview")} class="markdown-source-preview">
                {Phoenix.HTML.raw(@preview.html)}
              </section>
              <div :if={@preview && @data.policy != :follow} class="markdown-source-actions">
                <button type="button" class="markdown-source-button" phx-click="accept_version" phx-target={@myself}>
                  {gettext("Use displayed version")}
                </button>
                <span>{gettext("Included when you save the entry")}</span>
              </div>
            </div>
            <p :if={@error} role="alert">{@error}</p>
          </div>
        </Block.block>
      </.inputs_for>
    </div>
    """
  end

  def handle_event("preview", %{"markdown_preview_version" => id}, socket) do
    {:noreply, assign(socket, preview: MarkdownSources.get_version(socket.assigns.data.source_id, id), error: nil)}
  end

  def handle_event("refresh_versions", _, socket) do
    source = MarkdownSources.get_source(socket.assigns.data.source_id)

    {:noreply,
     assign(socket,
       source: source,
       versions: if(source, do: MarkdownSources.versions(source.id), else: []),
       active_version: MarkdownSources.resolved_version(socket.assigns.data)
     )}
  end

  def handle_event("accept_version", _, socket) do
    case socket.assigns.preview do
      %{source_id: source_id, id: id} when source_id == socket.assigns.data.source_id ->
        # The event carries no latest-version shortcut. It commits exactly the
        # immutable document displayed by this component, through the owner.
        data = Block.current_block_data_map(socket.assigns.block, nil, %{version_id: id})
        {:noreply, Block.commit_ref_data(socket, ref_data: data)}

      _ ->
        {:noreply, assign(socket, error: gettext("Preview a version before selecting it."))}
    end
  end
end
