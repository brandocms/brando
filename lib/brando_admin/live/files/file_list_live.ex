defmodule BrandoAdmin.Files.FileListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Files.File
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias Brando.Files

  @impl true
  def mount(_params, _session, socket) do
    socket =
      allow_upload(socket, :files,
        accept: :any,
        max_entries: 10,
        max_file_size: 50_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    # Files will auto-upload when selected
    {:noreply, socket}
  end

  def handle_progress(:files, entry, socket) do
    if entry.done? do
      # Process completed upload - consume the specific entry
      config_target = "default"
      {:ok, cfg} = Files.get_config_for(%{config_target: config_target})

      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             Files.Uploads.Schema.handle_upload(
               %{
                 "file" => %Plug.Upload{filename: entry.client_name, content_type: entry.client_type, path: path},
                 "config_target" => config_target
               },
               cfg,
               socket.assigns.current_user
             )
           end) do
        {:error, _changeset} ->
          send(self(), {:toast, gettext("Failed to upload file")})

        _file ->
          send(self(), {:toast, gettext("File uploaded successfully")})
          update_list_entries(socket.assigns.schema)
      end
    end

    {:noreply, socket}
  end

  defp update_list_entries(schema) do
    topic = "brando:listing:content_listing_#{schema}_default"
    Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {schema, [:entries, :updated], []})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Content.header title={gettext("Assets — Files")} subtitle={gettext("Overview")}>
      <form phx-change="validate" phx-drop-target={@uploads.files.ref}>
        <label class="btn-stealth">
          <span>{gettext("Upload Files")}</span>
          <.live_file_input upload={@uploads.files} class="hidden" />
        </label>
      </form>
    </Content.header>

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end
