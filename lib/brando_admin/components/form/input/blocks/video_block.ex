defmodule BrandoAdmin.Components.Form.Input.Blocks.VideoBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Brando.Gettext

  alias Brando.Villain
  alias Brando.Villain.Blocks.VideoBlock
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks

  # prop base_form, :any
  # prop data_field, :atom
  # prop block, :any
  # prop block_count, :integer
  # prop index, :any
  # prop is_ref?, :boolean, default: false
  # prop belongs_to, :string

  # prop insert_block, :event, required: true
  # prop duplicate_block, :event, required: true

  # data block_data, :any
  # data uid, :string

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def update(assigns, socket) do
    block_data =
      assigns.block
      |> inputs_for(:data)
      |> List.first()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(assigns.block, :uid))
     |> assign(:type, assigns.block.data.data.source)
     |> assign(:block_data, block_data)
     |> assign(:remote_id, v(block_data, :remote_id))
     |> assign(:source, v(block_data, :source))
     |> assign(:thumbnail_url, v(block_data, :thumbnail_url))
     |> assign(:title, v(block_data, :title))
     |> assign(:width, v(block_data, :width))
     |> assign(:height, v(block_data, :height))
     |> assign(:cover, v(block_data, :cover))
     |> assign(:cover_image, v(block_data, :cover_image))}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="video-block"
      data-block-index={@index}
      data-block-uid={@uid}>
      <Blocks.block
        id={"block-#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}
        wide_config>
        <:description>
          <%= if @type == :file do %>
            <%= gettext "External file" %>
          <% else %>
            <%= @type %>: <%= @remote_id %>
          <% end %>
        </:description>
        <:config>
          <%= if @remote_id in [nil, ""] do %>
            <Input.input type={:hidden} form={@block_data} field={:url} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:source} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:width} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:height} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:remote_id} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:thumbnail_url} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:title} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:poster} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:cover} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:opacity} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:autoplay} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:preload} uid={@uid} id_prefix="block_data" />
            <Input.input type={:hidden} form={@block_data} field={:play_button} uid={@uid} id_prefix="block_data" />

            <div id={"block-#{@uid}-videoUrl"} phx-hook="Brando.VideoURLParser" phx-update="ignore" data-target={@myself}>
              <%= gettext("Enter the video's URL:") %>
              <input id={"block-#{@uid}-url"} type="text" class="text">
              <button id={"block-#{@uid}-button"} type="button" class="secondary small">
                <%= gettext("Get video info") %>
              </button>
            </div>
          <% else %>
            <div class="panels">
              <div class="panel">
                <div class="cover" :if={@cover_image}>
                  <small><strong>Cover:</strong></small><br>
                  <Content.image image={@cover_image} size={:smallest} />
                </div>

                <div class="cover" :if={!@cover_image}>
                  <div class="img-placeholder">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M4.828 21l-.02.02-.021-.02H2.992A.993.993 0 0 1 2 20.007V3.993A1 1 0 0 1 2.992 3h18.016c.548 0 .992.445.992.993v16.014a1 1 0 0 1-.992.993H4.828zM20 15V5H4v14L14 9l6 6zm0 2.828l-6-6L6.828 19H20v-1.172zM8 11a2 2 0 1 1 0-4 2 2 0 0 1 0 4z"/></svg>
                  </div>
                </div>

                <div :if={@cover_image} class="button-group-vertical">
                  <button type="button" class="secondary" phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}>
                    <%= gettext("Select cover image") %>
                  </button>

                  <button type="button" class="danger" phx-click={JS.push("reset_image", target: @myself)}>
                    <%= gettext("Reset cover image") %>
                  </button>
                </div>

                <div class="information mb-1 mt-1">
                  <strong>Dimensions:</strong> <%= @width %>&times;<%= @height %>
                </div>
              </div>
              <div class="panel">
                <Input.input type={:hidden} form={@block_data} field={:source} uid={@uid} id_prefix="block_data" />
                <Input.input type={:hidden} form={@block_data} field={:thumbnail_url} uid={@uid} id_prefix="block_data" />
                <Input.text form={@block_data} field={:remote_id} uid={@uid} id_prefix="block_data" monospace label={gettext "Remote ID"} />
                <Input.text form={@block_data} field={:title} uid={@uid} id_prefix="block_data" label={gettext "Title"} />

                <div
                  :if={!@cover_image}
                  class="button-group-vertical">
                  <button type="button" class="secondary" phx-click={JS.push("set_target", target: @myself) |> toggle_drawer("#image-picker")}>
                    <%= gettext("Select cover image") %>
                  </button>

                  <button type="button" class="danger" phx-click={JS.push("reset_image", target: @myself)}>
                    <%= gettext("Reset cover image") %>
                  </button>
                </div>

                <Input.input type={:hidden} form={@block_data} field={:poster} uid={@uid} id_prefix="block_data" />
                <%= if @cover in ["false", "svg"] do %>
                  <Input.input type={:hidden} form={@block_data} field={:cover} uid={@uid} id_prefix="block_data" />
                <% else %>
                  <Input.text form={@block_data} field={:cover} uid={@uid} id_prefix="block_data" label={gettext "Cover"} />
                <% end %>

                <Input.input type={:hidden} form={@block_data} field={:opacity} uid={@uid} id_prefix="block_data" />

                <div class="row">
                  <div class="half">
                    <Input.number form={@block_data} field={:width} uid={@uid} id_prefix="block_data" label={gettext "Width"} />
                  </div>
                  <div class="half">
                    <Input.number form={@block_data} field={:height} uid={@uid} id_prefix="block_data" label={gettext "Height"} />
                  </div>
                </div>

                <div class="row">
                  <div class="half">
                    <Input.toggle compact form={@block_data} field={:play_button} uid={@uid} id_prefix="block_data" label={gettext "Play button"} />
                  </div>
                  <div class="half">
                    <Input.toggle compact form={@block_data} field={:autoplay} uid={@uid} id_prefix="block_data" label={gettext "Autoplay"} />
                  </div>
                </div>
                <div class="row">
                  <div class="half">
                    <Input.toggle compact form={@block_data} field={:preload} uid={@uid} id_prefix="block_data" label={gettext "Preload"} />
                  </div>
                  <div class="half">
                    <Input.toggle compact form={@block_data} field={:controls} uid={@uid} id_prefix="block_data" label={gettext "Show native player controls"} />
                  </div>
                </div>
                <%= if @cover_image do %>
                  <%= for cover_image <- inputs_for(@block_data, :cover_image) do %>
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:placeholder} />
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:cdn} />
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:moonwalk} />
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:lazyload} />
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:credits} />
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:dominant_color} />
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:height} />
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:width} />
                    <Input.input type={:hidden} form={cover_image} uid={@uid} id_prefix={"block_data"} field={:path} />

                    <Form.inputs
                      form={cover_image}
                      for={:focal}
                      let={%{form: focal_form}}>
                      <Input.input type={:hidden} form={focal_form} uid={@uid} id_prefix={"block_data_focal"} field={:x} />
                      <Input.input type={:hidden} form={focal_form} uid={@uid} id_prefix={"block_data_focal"} field={:y} />
                    </Form.inputs>

                    <Form.map_inputs
                      let={%{value: value, name: name}}
                      form={cover_image}
                      for={:sizes}>
                      <input type="hidden" name={"#{name}"} value={"#{value}"} />
                    </Form.map_inputs>

                    <Form.array_inputs
                      let={%{value: array_value, name: array_name}}
                      form={cover_image}
                      for={:formats}>
                      <input type="hidden" name={array_name} value={array_value} />
                    </Form.array_inputs>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </:config>
        <%= if @remote_id in [nil, ""] do %>
          <div class="empty">
            <figure>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0H24V24H0z"/><path d="M16 4c.552 0 1 .448 1 1v4.2l5.213-3.65c.226-.158.538-.103.697.124.058.084.09.184.09.286v12.08c0 .276-.224.5-.5.5-.103 0-.203-.032-.287-.09L17 14.8V19c0 .552-.448 1-1 1H2c-.552 0-1-.448-1-1V5c0-.552.448-1 1-1h14zm-1 2H3v12h12V6zM8 8h2v3h3v2H9.999L10 16H8l-.001-3H5v-2h3V8zm13 .841l-4 2.8v.718l4 2.8V8.84z"/></svg>
            </figure>
            <div class="instructions">
              <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")}><%= gettext "Configure video block" %></button>
            </div>
          </div>
        <% else %>
          <%= case @source do %>
            <% :vimeo -> %>
              <div class="video-content">
                <iframe
                  src={"https://player.vimeo.com/video/#{@remote_id}?title=0&byline=0"}
                  width="580" height="320" frameborder="0"></iframe>
              </div>

            <% :youtube -> %>
              <div class="video-content">
                <iframe
                  src={"https://www.youtube.com/embed/#{@remote_id}"}
                  width="580" height="320" frameborder="0"></iframe>
              </div>

            <% :file -> %>
              <div id={"block-#{@uid}-videoSize"}>
                <video class="villain-video-file" muted="muted" tabindex="-1" loop autoplay src={@remote_id}>
                  <source src={@remote_id} type="video/mp4">
                </video>
              </div>
          <% end %>
        <% end %>
      </Blocks.block>
    </div>
    """
  end

  def handle_event(
        "url",
        %{
          "remoteId" => remote_id,
          "source" => source,
          "url" => url,
          "width" => width,
          "height" => height
        },
        %{assigns: %{uid: uid, data_field: data_field, base_form: form}} = socket
      ) do
    # replace block
    changeset = form.source

    new_data = %{
      url: url,
      source: String.to_existing_atom(source),
      remote_id: remote_id
    }

    new_data =
      case Brando.OEmbed.get(source, url) do
        {:ok,
         %{
           "title" => title,
           "width" => width,
           "height" => height,
           "thumbnail_url" => thumbnail_url
         }} ->
          Map.merge(new_data, %{
            title: title,
            width: width,
            height: height,
            thumbnail_url: thumbnail_url
          })

        _ ->
          Map.merge(new_data, %{
            width: width,
            height: height
          })
      end

    updated_changeset =
      Villain.update_block_in_changeset(changeset, data_field, uid, %{data: new_data})

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end

  def handle_event(
        "set_target",
        _,
        %{assigns: %{myself: myself}} = socket
      ) do
    send_update(BrandoAdmin.Components.ImagePicker,
      id: "image-picker",
      config_target: "default",
      event_target: myself,
      multi: false,
      selected_images: []
    )

    {:noreply, socket}
  end

  def handle_event(
        "reset_image",
        _,
        %{
          assigns: %{
            base_form: base_form,
            block_data: block_data,
            block: block,
            data_field: data_field,
            uid: uid
          }
        } = socket
      ) do
    data_map = Map.from_struct(block_data.data)

    updated_data_map = Map.put(data_map, :cover_image, nil)
    updated_data_struct = struct(VideoBlock.Data, updated_data_map)

    updated_block = Map.put(block.data, :data, updated_data_struct)

    changeset = base_form.source
    schema = changeset.data.__struct__

    updated_changeset =
      Brando.Villain.replace_block_in_changeset(
        changeset,
        data_field,
        uid,
        updated_block
      )

    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end

  def handle_event(
        "select_image",
        %{"id" => id},
        %{
          assigns: %{
            base_form: base_form,
            uid: uid,
            block: block,
            block_data: block_data,
            data_field: data_field
          }
        } = socket
      ) do
    {:ok, image} = Brando.Images.get_image(id)

    data_map = Map.from_struct(block_data.data)

    updated_data_map = Map.put(data_map, :cover_image, image)
    updated_data_struct = struct(VideoBlock.Data, updated_data_map)

    updated_block = Map.put(block.data, :data, updated_data_struct)

    changeset = base_form.source
    schema = changeset.data.__struct__

    updated_changeset =
      Brando.Villain.replace_block_in_changeset(
        changeset,
        data_field,
        uid,
        updated_block
      )

    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end
end
