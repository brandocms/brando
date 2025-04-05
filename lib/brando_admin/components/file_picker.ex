defmodule BrandoAdmin.Components.FilePicker do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Utils
  alias BrandoAdmin.Components.Content

  def update(
        %{config_target: config_target, event_target: event_target, multi: multi, selected_files: selected_files},
        socket
      ) do
    {:ok,
     socket
     |> assign(:config_target, config_target)
     |> assign(:event_target, event_target)
     |> assign(:multi, multi)
     |> assign(:selected_files, selected_files)
     |> assign_files()}
  end

  def update(%{selected_files: selected_files}, socket) do
    {:ok, assign(socket, :selected_files, selected_files)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:multi, fn -> false end)
     |> assign_new(:files, fn -> [] end)
     |> assign_new(:config_target, fn -> nil end)
     |> assign_new(:event_target, fn -> nil end)
     |> assign_new(:z_index, fn -> 1100 end)
     |> assign_new(:deselect_file, fn -> nil end)
     |> assign_new(:selected_files, fn -> [] end)}
  end

  def assign_files(socket) do
    {:ok, files} =
      Brando.Files.list_files(%{
        select: [:id, :filename, :cdn, :config_target, :filesize],
        filter: %{config_target: socket.assigns.config_target},
        order: "desc id"
      })

    assign(socket, :files, files)
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.drawer id={@id} title={gettext("Select file")} close={toggle_drawer("##{@id}")} z={@z_index} dark>
        <:info>
          <%= if @config_target do %>
            <div class="mb-2">
              {gettext("Select similarly typed file from library")}
            </div>
          <% end %>
        </:info>

        <div class="file-picker list" id={"file-picker-drawer-#{@id}"}>
          <%= for file <- @files do %>
            <div
              class={["file-picker__file", file.filename in @selected_files && "selected"]}
              phx-click={
                if @multi,
                  do: JS.push("select_file", target: @event_target),
                  else: JS.push("select_file", target: @event_target) |> toggle_drawer("#file-picker")
              }
              phx-value-id={file.id}
              phx-value-selected={(file.filename in @selected_files && "true") || "false"}
            >
              <div class="file-picker__info">
                <div class="file-picker__filename">#{file.id} {Utils.file_url(file)}</div>
                <div class="file-picker__size">({Brando.Utils.human_size(file.filesize)})</div>
              </div>
            </div>
          <% end %>
        </div>
      </Content.drawer>
    </div>
    """
  end
end
