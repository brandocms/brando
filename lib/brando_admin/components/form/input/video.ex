defmodule BrandoAdmin.Components.Form.Input.Video do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Ecto.Changeset

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input

  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data class, :string
  # data monospace, :boolean
  # data disabled, :boolean
  # data debounce, :integer
  # data compact, :boolean

  # data video, :any
  # data file_name, :any
  # data upload_field, :any
  # data relation_field, :atom

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
     |> assign_new(:small, fn -> false end)
     |> assign_new(:placeholder, fn -> nil end)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
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

    {socket, video} =
      cond do
        is_nil(video) && video_id ->
          # we have a video in the changeset, but no loaded video
          {:ok, video} = Brando.Videos.get_video(video_id)

          {socket
           |> assign(:video, video)
           |> assign(:video_id, video_id), video}

        video && to_string(video.id) != to_string(video_id) && video_id != nil ->
          # we have a loaded video, but it does not match the changeset video
          # load the changeset video
          {:ok, video} = Brando.Videos.get_video(video_id)

          {socket
           |> assign(:video, video)
           |> assign(:video_id, video_id), video}

        video && video.id == nil && video_id == nil ->
          # no loaded video, no video_id in changeset
          # try to fetch by path?

          video_id =
            changeset
            |> EctoNestedChangeset.get_at(full_path_fk)
            |> try_force_int()

          {:ok, video} = Brando.Videos.get_video(video_id)

          {socket
           |> assign(:video, video)
           |> assign(:video_id, video_id), video}

        video_id == nil && video != nil ->
          # reset video to nil
          {socket
           |> assign(:video_id, nil)
           |> assign(:video, nil), nil}

        video_id != socket.assigns.video_id ->
          {assign(socket, :video_id, video_id), video}

        video && video_from_changeset && 
            (video.title != video_from_changeset.title ||
             video.caption != video_from_changeset.caption) ->
          # we have a video, and a video from the changeset where the changeset video
          # has updated title or caption. lets just grab the video from changeset
          {assign(socket, :video, video_from_changeset), video_from_changeset}

        true ->
          {socket, video}
      end

    file_name = get_file_name(video)

    {:ok,
     socket
     |> prepare_input_component()
     |> assign(:file_name, file_name)
     |> assign_new(:editable, fn -> Keyword.get(socket.assigns.opts, :editable, true) end)
     |> assign_new(:upload_field, fn -> socket.assigns.parent_uploads[assigns.field.field] end)
     |> assign_new(:relation_field, fn -> relation_field end)}
  end

  def try_force_int(str) when is_binary(str), do: String.to_integer(str)
  def try_force_int(int) when is_integer(int), do: int
  def try_force_int(val), do: val

  defp get_file_name(nil), do: nil
  defp get_file_name(%{type: :upload, file: %{filename: filename}}), do: filename
  defp get_file_name(%{type: :upload}), do: nil
  defp get_file_name(%{type: type, source_url: source_url}) when type in [:vimeo, :youtube, :external_file] and not is_nil(source_url), do: source_url
  defp get_file_name(%{type: type, remote_id: remote_id}) when type in [:vimeo, :youtube] and not is_nil(remote_id), do: "#{type}:#{remote_id}"
  defp get_file_name(_), do: nil

  def render(assigns) do
    ~H"""
    <div>
      <Form.field_base :if={@editable} field={@field} label={@label} instructions={@instructions} class={@class} relation>
        <div>
          <div class={["input-video", @small && "small"]}>
            <.video_preview
              video={@video}
              field={@field}
              relation_field={@relation_field}
              click={@editable && open_video(@myself)}
              editable={@editable}
              file_name={@file_name}
            />
          </div>
        </div>
      </Form.field_base>
      <div :if={!@editable} class={["input-video", @small && "small"]}>
        <.video_preview
          video={@video}
          field={@field}
          relation_field={@relation_field}
          click={@editable && open_video(@myself)}
          editable={@editable}
          file_name={@file_name}
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

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:active_field:#{entry_id}",
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
      selected_videos: []
    )

    form_id = "#{module.__naming__().singular}_form"

    edit_video = %{
      id: video_id,
      path: path,
      field: field_name,
      relation_field: relation_field,
      schema: form.data.__struct__,
      form_id: form_id,
      video: video
    }

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_edit_video,
      edit_video: edit_video
    )

    {:noreply,
     socket
     |> assign(:path, path)
     |> assign(:form_id, form_id)}
  end

  def handle_event("select_video", %{"id" => selected_video_id}, %{assigns: %{form_id: form_id}} = socket) do
    on_change = socket.assigns.on_change
    {:ok, video} = Brando.Videos.get_video(selected_video_id)

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

  @doc """
  Show preview if we have a video
  """
  def video_preview(assigns) do
    assigns =
      assigns
      |> assign_new(:size, fn -> nil end)
      |> assign_new(:value, fn -> nil end)
      |> assign_new(:editable, fn -> true end)
      |> assign_new(:publish, fn -> false end)
      |> assign_new(:video_id, fn ->
        if assigns[:video] do
          assigns[:video].id
        end
      end)

    ~H"""
    <div class="video-wrapper-compact">
      <Input.input :if={@editable} type={:hidden} field={@relation_field} value={@value || @video_id} publish={@publish} />
      <%= if @video do %>
        <div class="video-preview">
          <%= case @video.type do %>
            <% :upload -> %>
              <div class="img-placeholder">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
                </svg>
              </div>
            <% type when type in [:vimeo, :youtube, :external_file] -> %>
              <%= if @video.thumbnail do %>
                <Content.image image={@video.thumbnail} size={:thumb} />
              <% else %>
                <div class="img-placeholder">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                    <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
                  </svg>
                </div>
              <% end %>
            <% _ -> %>
              <div class="img-placeholder">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
                  <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
                </svg>
              </div>
          <% end %>
        </div>
        <div :if={@editable} class="video-info">
          <div class="info-wrapper">
            <div class="filename">{@file_name || gettext("Untitled video")}</div>
            <div :if={@video.width && @video.height} class="dims">{@video.width}&times;{@video.height}</div>
            <div :if={@video.title} class="title">● {@video.title}</div>
            <div class="type badge tiny">{@video.type}</div>
          </div>
          <button class="tiny" type="button" phx-click={@click}>
            {gettext("Edit video")}
          </button>
        </div>
      <% else %>
        <div class="img-placeholder">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
            <path fill="none" d="M0 0h24v24H0z" /><path d="M3 3.993C3 3.445 3.445 3 3.993 3h16.014c.548 0 .993.445.993.993v16.014a.994.994 0 0 1-.993.993H3.993A.994.994 0 0 1 3 20.007V3.993zM5 5v14h14V5H5zm5.622 3.415l4.879 3.252a.4.4 0 0 1 0 .666l-4.88 3.252a.4.4 0 0 1-.621-.332V8.747a.4.4 0 0 1 .622-.332z" />
          </svg>
        </div>

        <div :if={@editable} class="video-info">
          {gettext("No video associated with field")}
          <button class="tiny" type="button" phx-click={@click} phx-value-id={"edit-video-#{@field.id}"}>
            {gettext("Add video")}
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end