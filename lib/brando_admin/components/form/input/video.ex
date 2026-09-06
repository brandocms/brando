defmodule BrandoAdmin.Components.Form.Input.Video do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Primitives

  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:opts, fn -> [] end)
     |> assign_new(:previous_video_id, fn -> nil end)
     |> assign_new(:label, fn -> nil end)
     |> assign_new(:instructions, fn -> nil end)
     |> assign_new(:path, fn -> [] end)
     |> assign_new(:video, fn -> nil end)
     |> assign_new(:video_id, fn -> nil end)
     |> assign_new(:parent_form, fn -> nil end)
     |> assign_new(:placeholder, fn -> nil end)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> then(&assign(&1, :defaults, field_defaults(&1.assigns.opts)))
      |> assign_new(:form_id, fn ->
        form = assigns.field.form
        path = Brando.Utils.get_path_from_field_name(form.name)
        module_from_form = form.source.data.__struct__

        module =
          if path == [] do
            module_from_form
          else
            Brando.Utils.get_parent_module_from_field_name(form.name, module_from_form)
          end

        "#{module.__naming__().singular}_form"
      end)

    relation_field_atom = String.to_existing_atom("#{assigns.field.field}_id")
    relation_field = assigns.field.form[relation_field_atom]
    changeset = assigns.field.form.source

    full_path_fk = socket.assigns.path ++ [relation_field_atom]

    video_id =
      changeset
      |> get_field(relation_field_atom)
      |> try_force_int()

    video_from_changeset = get_field(changeset, assigns.field.field)
    video = socket.assigns.video

    socket =
      cond do
        is_nil(video) && video_id ->
          # we have a video in the changeset, but no loaded video
          fetch_video(socket, video_id)

        video && to_string(video.id) != to_string(video_id) && video_id != nil ->
          # we have a loaded video, but it does not match the changeset video
          # load the changeset video
          fetch_video(socket, video_id)

        video && video.id == nil && video_id == nil ->
          # no loaded video, no video_id in changeset
          # try to fetch by path?

          video_id =
            changeset
            |> EctoNestedChangeset.get_at(full_path_fk)
            |> try_force_int()

          fetch_video(socket, video_id)

        video_id == nil && video != nil ->
          # reset video to nil
          socket
          |> assign(:video_id, nil)
          |> assign(:video, nil)

        video_id != socket.assigns.video_id ->
          socket
          |> assign(:video_id, video_id)
          |> maybe_subscribe(video_id)

        # we have a video, and a video from the changeset, but the title or caption has changed
        video && video_from_changeset &&
            (video.title != video_from_changeset.title ||
               video.caption != video_from_changeset.caption) ->
          assign(socket, :video, video_from_changeset)

        true ->
          if video && video.status != :ready do
            # if the video is not ready, we can try to reload and see if it's done.
            # A failed reload keeps the video we already have — it is only a refresh.
            case Brando.Videos.get_video(video_id) do
              {:ok, reloaded_video} -> assign(socket, :video, reloaded_video)
              {:error, _} -> socket
            end
          else
            socket
          end
      end

    {:ok,
     socket
     |> prepare_input_component()
     |> assign_new(:editable, fn -> Keyword.get(socket.assigns.opts, :editable, true) end)
     |> assign_new(:relation_field, fn -> relation_field end)}
  end

  # Field-level defaults for a *new* video, from the form input:
  #
  #     input :video, :video, defaults: %{loop: true, muted: true}
  #
  # `BrandoAdmin.Components.Form` merges these onto the blank `%Video{}` before
  # building the drawer's changeset, so the drawer's switches show them and
  # saving persists them. They set the video *record*, which is the middle layer
  # of the resolution chain — a block or `{% video %}` override still wins over
  # them at render time, and they in turn beat `Brando.HTML.Video`'s built-ins.
  defp field_defaults(opts) do
    case Keyword.get(opts, :defaults, %{}) do
      %{} = defaults -> validate_defaults!(defaults)
      other -> raise ArgumentError, "video input `defaults` must be a map, got: #{inspect(other)}"
    end
  end

  # A key the video schema cannot hold would be dropped by `struct/2` without a
  # word, and the field would silently keep rendering its built-in default.
  defp validate_defaults!(defaults) do
    case Map.keys(defaults) -- Map.keys(Map.from_struct(%Brando.Videos.Video{})) do
      [] ->
        defaults

      unknown ->
        raise ArgumentError, """
        video input `defaults` has no field on Brando.Videos.Video for #{inspect(unknown)}.

        Settable defaults are the video's own columns, e.g. `autoplay`, `preload`,
        `loop`, `muted`, `controls`, `aspect_ratio`.
        """
    end
  end

  # Mirrors `input/image.ex`'s `fetch_image/2`: a referenced video may have been
  # hard-deleted, and `video_id` can legitimately be nil on the path lookup. A
  # hard match here raised MatchError and destroyed the whole entry form process
  # along with every unsaved change in it. Fall back to the empty picker state.
  defp fetch_video(socket, video_id) do
    case Brando.Videos.get_video(%{matches: %{id: video_id}, preload: [:thumbnail]}) do
      {:ok, video} ->
        socket
        |> assign(:video, video)
        |> assign(:video_id, video_id)
        |> maybe_subscribe(video_id)

      {:error, _} ->
        socket
        |> assign(:video, nil)
        |> assign(:video_id, nil)
    end
  end

  defp maybe_subscribe(socket, video_id) when is_integer(video_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:video:#{video_id}", link: true)
    end

    socket
  end

  defp maybe_subscribe(socket, _), do: socket

  def try_force_int(str) when is_binary(str), do: String.to_integer(str)
  def try_force_int(int) when is_integer(int), do: int
  def try_force_int(val), do: val

  def render(assigns) do
    ~H"""
    <div>
      <Primitives.field_base
        :if={@editable}
        field={@field}
        label={@label}
        instructions={@instructions}
        class={@class}
        relation
      >
        <div>
          <div class="input-video">
            <.video_preview
              video={@video}
              field={@field}
              relation_field={@relation_field}
              click={@editable && open_video(@myself)}
              editable={@editable}
            />
          </div>
        </div>
      </Primitives.field_base>
      <%!-- `click={false}`: this branch only renders when `@editable` is false,
            so the old `@editable && open_video(...)` could never be anything
            else. --%>
      <div :if={!@editable} class="input-video">
        <.video_preview
          video={@video}
          field={@field}
          relation_field={@relation_field}
          click={false}
          editable={@editable}
        />
      </div>
    </div>
    """
  end

  def open_video(js \\ %JS{}, target) do
    js
    |> JS.push("open_video", target: target)
    |> toggle_drawer("#video-drawer")
  end

  def handle_event("open_video", _, socket) do
    field = socket.assigns.field
    field_name = field.field
    form = field.form
    entry_id = form.data.id
    relation_field = socket.assigns.relation_field
    video_id = socket.assigns.video_id
    video = socket.assigns.video
    myself = socket.assigns.myself
    current_user = socket.assigns.current_user
    defaults = socket.assigns.defaults

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.entry("active_field", form.data.__struct__, entry_id),
      {:active_field, field.name, current_user.id}
    )

    path = Brando.Utils.get_path_from_field_name(form.name)
    module_from_form = form.source.data.__struct__

    module =
      if path == [] do
        module_from_form
      else
        Brando.Utils.get_parent_module_from_field_name(form.name, module_from_form)
      end

    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      config_target: {"video", form.data.__struct__, field_name},
      event_target: myself,
      multi: false,
      selected_videos: if(video_id, do: [video_id], else: [])
    )

    form_id = "#{module.__naming__().singular}_form"

    edit_video = %{
      id: video_id,
      path: path,
      field: field_name,
      relation_field: relation_field,
      schema: form.data.__struct__,
      form_id: form_id,
      video: video,
      defaults: defaults
    }

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :open_video_drawer,
      video_context: :asset,
      edit_video: edit_video
    )

    {:noreply,
     socket
     |> assign(:path, path)
     |> assign(:form_id, form_id)}
  end

  def handle_event("select_video", %{"id" => selected_video_id}, %{assigns: %{form_id: form_id}} = socket) do
    on_change = socket.assigns.on_change
    {:ok, video} = Brando.Videos.get_video(%{matches: %{id: selected_video_id}, preload: [:thumbnail, :file]})

    send_update(BrandoAdmin.Components.VideoPicker,
      id: "video-picker",
      selected_videos: [video.id]
    )

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_edit_video,
      video: video
    )

    if on_change do
      path = socket.assigns.path
      field_name = socket.assigns.field.field
      field_path = path ++ [field_name]

      on_change.(%{
        event: "update_entry_relation",
        path: field_path,
        updated_relation: video
      })
    end

    {:noreply, socket}
  end

  # Handle real-time video updates
  def handle_info({video, [:video, :updated]}, socket) do
    {:noreply, assign(socket, :video, video)}
  end

  @doc """
  Show preview if we have a video
  """
  def video_preview(assigns) do
    assigns =
      assigns
      |> assign_new(:editable, fn -> true end)
      |> assign_new(:publish, fn -> false end)
      |> assign_new(:video_id, fn ->
        if assigns[:video] do
          assigns[:video].id
        end
      end)
      |> assign_new(:provider_thumbnail_url, fn ->
        if assigns[:video], do: Brando.Videos.Helpers.thumbnail_url(assigns[:video])
      end)

    ~H"""
    <div class="asset-field asset-field--single video-wrapper-compact">
      <Input.input :if={@editable} type={:hidden} field={@relation_field} value={@video_id} publish={@publish} />
      <%= if @video do %>
        <%= if @video.status == :ready do %>
          <%= if @provider_thumbnail_url do %>
            <img src={@provider_thumbnail_url} alt={@video.title || "Video thumbnail"} />
          <% else %>
            <%= if @video.thumbnail do %>
              <Content.image image={@video.thumbnail} size={:thumb} />
            <% else %>
              <.video_placeholder />
            <% end %>
          <% end %>
        <% else %>
          <.processing_placeholder />
        <% end %>
        <div :if={@editable} class="video-info">
          <div class="info-wrapper">
            <div class="type">
              <%= case @video.type do %>
                <% :mux -> %>
                  Mux
                <% :bunny -> %>
                  Bunny Stream
                <% :cloudflare -> %>
                  Cloudflare Stream
                <% :upload -> %>
                  Upload
                <% :vimeo -> %>
                  Vimeo
                <% :youtube -> %>
                  YouTube
                <% _ -> %>
                  Video
              <% end %>
            </div>
            <div class="title-row">
              <.status_indicator status={@video.status} />
              <div :if={@video.title} class="title">{@video.title}</div>
            </div>
            <%= if @video.type == :mux && get_in(@video.meta, ["mux", "duration"]) do %>
              <% duration = get_in(@video.meta, ["mux", "duration"]) %>
              <div class="meta">{format_duration(duration)}</div>
            <% end %>
          </div>
          <button class="tiny" type="button" phx-click={@click}>
            {gettext("Edit video")}
          </button>
        </div>
      <% else %>
        <.video_placeholder />
        <div :if={@editable} class="video-info">
          <span>{gettext("No video associated with field")}</span>
          <button class="tiny" type="button" phx-click={@click} phx-value-id={"edit-video-#{@field.id}"}>
            {gettext("Add video")}
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp video_placeholder(assigns) do
    ~H"""
    <div class="video-placeholder">
      <.icon name="hero-video-camera" />
    </div>
    """
  end

  defp processing_placeholder(assigns) do
    ~H"""
    <div class="video-placeholder">
      <svg class="spin" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="48" height="48">
        <path fill="none" d="M0 0h24v24H0z" /><path d="M5.463 4.433A9.961 9.961 0 0 1 12 2c5.523 0 10 4.477 10 10 0 2.136-.67 4.116-1.81 5.74L17 12h3A8 8 0 0 0 6.46 6.228l-.997-1.795zm13.074 15.134A9.961 9.961 0 0 1 12 22C6.477 22 2 17.523 2 12c0-2.136.67-4.116 1.81-5.74L7 12H4a8 8 0 0 0 13.54 5.772l.997 1.795z" />
      </svg>
    </div>
    """
  end

  defp status_indicator(assigns) do
    status_class =
      case assigns.status do
        :ready -> "ready"
        :uploading -> "uploading"
        :processing -> "processing"
        :errored -> "errored"
        _ -> "pending"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <span class={"status-indicator #{@status_class}"}></span>
    """
  end

  defp format_duration(seconds) when is_number(seconds) do
    total_seconds = round(seconds)
    minutes = div(total_seconds, 60)
    remaining_seconds = rem(total_seconds, 60)

    if minutes > 0 do
      "#{minutes}:#{String.pad_leading(to_string(remaining_seconds), 2, "0")}"
    else
      "0:#{String.pad_leading(to_string(total_seconds), 2, "0")}"
    end
  end

  defp format_duration(_), do: ""
end
