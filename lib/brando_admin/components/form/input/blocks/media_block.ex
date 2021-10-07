defmodule BrandoAdmin.Components.Form.Input.Blocks.MediaBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Brando.Gettext

  alias BrandoAdmin.Components.Form.Input.Blocks.Block

  prop block, :form
  prop base_form, :form
  prop index, :integer
  prop block_count, :integer
  prop is_ref?, :boolean, default: false
  prop ref_description, :string
  prop belongs_to, :string
  prop data_field, :atom

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data text_type, :string
  data initial_props, :map
  data block_data, :map
  data available_blocks, :list

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    block_data = List.first(inputs_for(assigns.block, :data))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:block_data, block_data)
     |> assign(:available_blocks, input_value(block_data, :available_blocks))
     |> assign(:uid, v(assigns.block, :uid))}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-wrapper"}
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
        duplicate_block={@duplicate_block}>
        <:description>
          {#if @ref_description}
            {@ref_description}
          {/if}
        </:description>
        <div class="media-block">
          <div class="empty">
            <figure>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M11.27 12.216L15 6l8 15H2L9 8l2.27 4.216zm1.12 2.022L14.987 19h4.68l-4.77-8.942-2.507 4.18zM5.348 19h7.304L9 12.219 5.348 19zM5.5 8a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z"/></svg>
            </figure>
            <div class="instructions">
              Select media type:
            </div>
            <div class="buttons">
              {#if "picture" in @available_blocks}
                <button type="button" class="tiny" :on-click="select_block" phx-value-block="picture">{gettext("Picture")}</button>
              {/if}
              {#if "video" in @available_blocks}
                <button type="button" class="tiny" :on-click="select_block" phx-value-block="video">{gettext("Video")}</button>
              {/if}
              {#if "gallery" in @available_blocks}
                <button type="button" class="tiny" :on-click="select_block" phx-value-block="gallery">{gettext("Gallery")}</button>
              {/if}
              {#if "svg" in @available_blocks}
                <button type="button" class="tiny" :on-click="select_block" phx-value-block="svg">SVG</button>
              {/if}
            </div>
          </div>
        </div>
      </Block>
    </div>
    """
  end

  def handle_event(
        "select_block",
        %{"block" => block},
        %{assigns: %{uid: uid, data_field: data_field, base_form: form, block_data: block_data}} =
          socket
      ) do
    # replace block
    changeset = form.source

    new_block =
      case block do
        "picture" ->
          data_tpl = input_value(block_data, :template_picture)

          %Brando.Blueprint.Villain.Blocks.PictureBlock{
            uid: Brando.Utils.generate_uid(),
            type: "picture",
            data: data_tpl
          }

        "video" ->
          data_tpl = input_value(block_data, :template_video)

          %Brando.Blueprint.Villain.Blocks.VideoBlock{
            uid: Brando.Utils.generate_uid(),
            type: "video",
            data: data_tpl
          }

        "gallery" ->
          data_tpl = input_value(block_data, :template_gallery)

          %Brando.Blueprint.Villain.Blocks.GalleryBlock{
            uid: Brando.Utils.generate_uid(),
            type: "gallery",
            data: data_tpl
          }

        "svg" ->
          data_tpl = input_value(block_data, :template_svg)

          %Brando.Blueprint.Villain.Blocks.SvgBlock{
            uid: Brando.Utils.generate_uid(),
            type: "svg",
            data: data_tpl
          }
      end

    updated_changeset =
      Brando.Villain.replace_block_in_changeset(changeset, data_field, uid, new_block)

    schema = changeset.data.__struct__
    form_id = "#{schema.__naming__().singular}_form"

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
