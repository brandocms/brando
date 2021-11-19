defmodule BrandoAdmin.Components.Form.MetaDrawer do
  use BrandoAdmin, :component
  import Brando.Gettext
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Content

  # prop form, :form, required: true
  # prop blueprint, :any, required: true
  # prop uploads, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  def render(assigns) do
    ~H"""
    <Content.drawer id={@id} title={"Meta properties"} close={@close}>
      <:info>
        <p>
          <%= gettext ~s(
          Meta information for search engines. Try to keep the title tag below 70
          characters while incorporating key terms for your content. The description
          tag should be around 155 characters to prevent getting truncated in search
          results. You can also attach your own META image which will override your
          entry's cover image, if it has one.
          ) %>
        </p>
      </:info>
      <div class="brando-input">
        <Input.Text.render field={:meta_title} form={@form} label={gettext "META title"} />
      </div>

      <div class="brando-input">
        <Input.Textarea.render field={:meta_description} form={@form} label={gettext "META description"} />
      </div>

      <div class="brando-input">
        <.live_component
          module={Input.Image}
          id={"#{@form.id}-meta-image"}
          field={:meta_image}
          uploads={@uploads}
          form={@form}
          label={gettext "META image"} />
      </div>
    </Content.drawer>
    """
  end
end
