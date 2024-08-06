defmodule BrandoAdmin.Components.Form.MetaDrawer do
  use BrandoAdmin, :component
  import Brando.Gettext
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Content

  # prop form, :form, required: true
  # prop blueprint, :any, required: true
  # prop parent_uploads, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  def render(assigns) do
    ~H"""
    <Content.drawer id={@id} title={gettext("Meta properties")} close={@close}>
      <:info>
        <p>
          <%= gettext(
            "Meta information for search engines. Try to keep the title tag below 70 characters while incorporating key terms for your content. The description tag should be around 155 characters to prevent getting truncated in search results. You can also attach your own META image which will override your entry's cover image, if it has one."
          ) %>
        </p>
      </:info>
      <div class="brando-input">
        <Input.text field={@form[:meta_title]} label={gettext("META title")} />
      </div>

      <div class="brando-input">
        <Input.textarea field={@form[:meta_description]} label={gettext("META description")} />
      </div>

      <div class="brando-input">
        <.live_component
          module={Input.Image}
          id={"#{@form.id}-meta-image"}
          field={@form[:meta_image]}
          parent_uploads={@parent_uploads}
          label={gettext("META image")}
        />
      </div>
    </Content.drawer>
    """
  end
end
