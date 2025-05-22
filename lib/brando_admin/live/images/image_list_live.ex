defmodule BrandoAdmin.Images.ImageListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Images.Image
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias Brando.Images

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> allow_upload(:images,
        accept: ~w(.jpg .jpeg .png .gif .webp .avif .svg),
        max_entries: 10,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    # Images will auto-upload when selected
    {:noreply, socket}
  end

  def handle_progress(:images, entry, socket) do
    if entry.done? do
      # Process completed upload - consume the specific entry
      config_target = "default"
      {:ok, cfg} = Images.get_config_for(%{config_target: config_target})

      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             Images.Uploads.Schema.handle_upload(
               %{
                 "image" => %Plug.Upload{filename: entry.client_name, content_type: entry.client_type, path: path},
                 "config_target" => config_target
               },
               cfg,
               socket.assigns.current_user
             )
           end) do
        {:error, _changeset} ->
          send(self(), {:toast, gettext("Failed to upload image")})

        _image ->
          send(self(), {:toast, gettext("Image uploaded successfully")})
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
    <Content.header title={gettext("Assets — Images")} subtitle={gettext("Overview")}>
      <form phx-change="validate" phx-drop-target={@uploads.images.ref}>
        <label class="btn-stealth">
          <span>{gettext("Upload Images")}</span>
          <.live_file_input upload={@uploads.images} class="hidden" />
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
