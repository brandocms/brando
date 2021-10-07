defmodule BrandoAdmin.Components.Form.Input.Blocks.VideoBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks.Block
  alias BrandoAdmin.Components.Modal

  prop base_form, :any
  prop data_field, :atom
  prop block, :any
  prop block_count, :integer
  prop index, :any
  prop is_ref?, :boolean, default: false
  prop belongs_to, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data block_data, :any
  data uid, :string

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
     |> assign(:block_data, block_data)}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-wrapper"}
      class="video-block"
      data-block-index={@index}
      data-block-uid={@uid}>
      <Block
        id={"#{@uid}-base"}
        index={@index}
        is_ref?={@is_ref?}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}
        wide_config>
        <:description>{v(@block_data, :url)}</:description>
        <:config>
          {#if v(@block_data, :remote_id)}
            <div class="panels">
              <div class="panel">
                <img src={v(@block_data, :thumbnail_url)} />
                <div class="information">
                  <strong>Title:</strong> {v(@block_data, :title)}<br>
                  <strong>Dimensions:</strong> {v(@block_data, :width)}&times;{v(@block_data, :height)}
                </div>
              </div>
              <div class="panel">
                {hidden_input @block_data, :url}
                {hidden_input @block_data, :source}
                {hidden_input(@block_data, :width)}
                {hidden_input(@block_data, :height)}
                {hidden_input(@block_data, :remote_id)}
                {hidden_input(@block_data, :thumbnail_url)}

                <Input.Text form={@block_data} field={:title} />
                <Input.Text form={@block_data} field={:poster} />
                {#if v(@block_data, :cover) in ["false", "svg"]}
                  {hidden_input(@block_data, :cover)}
                {#else}
                  <Input.Text form={@block_data} field={:cover} />
                {/if}

                {hidden_input(@block_data, :opacity)}
                {hidden_input(@block_data, :play_button)}

                <Input.Toggle form={@block_data} field={:autoplay} />
                <Input.Toggle form={@block_data} field={:preload} />
              </div>
            </div>
          {#else}
            {hidden_input @block_data, :url}
            {hidden_input @block_data, :source}
            {hidden_input(@block_data, :width)}
            {hidden_input(@block_data, :height)}
            {hidden_input(@block_data, :remote_id)}
            {hidden_input(@block_data, :thumbnail_url)}
            {hidden_input(@block_data, :title)}
            {hidden_input(@block_data, :poster)}
            {hidden_input(@block_data, :cover)}
            {hidden_input(@block_data, :opacity)}
            {hidden_input(@block_data, :autoplay)}
            {hidden_input(@block_data, :preload)}
            {hidden_input(@block_data, :play_button)}

            <div id={"#{@uid}-videoUrl"} phx-hook="Brando.VideoURLParser" phx-update="ignore" data-target={@myself}>
              {gettext("Enter the video's URL:")}
              <input id={"#{@uid}-url"} type="text" class="text">
              <button id={"#{@uid}-button"} type="button" class="secondary small">
                {gettext("Get video info")}
              </button>
            </div>
          {/if}
        </:config>
        {#if v(@block_data, :remote_id)}
          {#case v(@block_data, :source)}
            {#match :vimeo}
              <div class="video-content">
                <iframe
                  src={"https://player.vimeo.com/video/#{v(@block_data, :remote_id)}?title=0&byline=0"}
                  width="580" height="320" frameborder="0"></iframe>
              </div>

            {#match :youtube}
              <div class="video-content">
                <iframe
                  src={"https://www.youtube.com/embed/#{v(@block_data, :remote_id)}"}
                  width="580" height="320" frameborder="0"></iframe>
              </div>

            {#match :file}
              <video class="villain-video-file" muted="muted" tabindex="-1" loop autoplay src={v(@block_data, :remote_id)}>
                <source src={v(@block_data, :remote_id)} type="video/mp4">
              </video>
          {/case}
        {#else}
          <div class="empty">
            <figure>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0H24V24H0z"/><path d="M16 4c.552 0 1 .448 1 1v4.2l5.213-3.65c.226-.158.538-.103.697.124.058.084.09.184.09.286v12.08c0 .276-.224.5-.5.5-.103 0-.203-.032-.287-.09L17 14.8V19c0 .552-.448 1-1 1H2c-.552 0-1-.448-1-1V5c0-.552.448-1 1-1h14zm-1 2H3v12h12V6zM8 8h2v3h3v2H9.999L10 16H8l-.001-3H5v-2h3V8zm13 .841l-4 2.8v.718l4 2.8V8.84z"/></svg>
            </figure>
            <div class="instructions">
              <button type="button" class="tiny" :on-click="show_config">Configure video block</button>
            </div>
          </div>
        {/if}

      </Block>
    </div>
    """
  end

  def handle_event("show_config", _, socket) do
    Modal.show("#{socket.assigns.uid}_config")
    {:noreply, socket}
  end

  def handle_event(
        "url",
        %{"remoteId" => remote_id, "source" => source, "url" => url},
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
          new_data
      end

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, uid, %{data: new_data})

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
