defmodule BrandoAdmin.Components.Form.MetaDrawer do
  use BrandoAdmin, :live_component
  import Brando.HTML, only: [render_classes: 1]
  alias BrandoAdmin.Components.Form.Input

  # prop form, :form, required: true
  # prop blueprint, :any, required: true
  # prop uploads, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  def render(assigns) do
    ~H"""
    <div class={render_classes(["drawer", "meta-drawer", open: @status == :open])}>
      <div class="inner">
        <div class="drawer-header">
          <h2>
            Meta properties
          </h2>
          <button
            phx-click={@close}
            type="button"
            class="drawer-close-button">
            Close
          </button>
        </div>
        <div class="drawer-info">
          <p>
            Meta information for search engines. Try to keep the title tag below 70 characters while incorporating key terms for your content. The description tag should be around 155 characters to prevent getting truncated in search results. You can also attach your own META image which will override your entry's cover image, if it has one.
          </p>
        </div>
        <div class="drawer-form">
          <div class="brando-input">
            <Input.Text.render field={:meta_title} form={@form} />
          </div>

          <div class="brando-input">
            <Input.Textarea.render field={:meta_description} form={@form} />
          </div>

          <div class="brando-input">
            <.live_component
              module={Input.Image}
              id={"#{@form.id}-meta-image"}
              field={:meta_image}
              uploads={@uploads}
              form={@form} />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
