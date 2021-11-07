defmodule BrandoAdmin.Components.Form.ScheduledPublishingDrawer do
  use BrandoAdmin, :component
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input

  # prop form, :form, required: true
  # prop blueprint, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  def render(assigns) do
    ~H"""
    <Content.drawer id={@id} heading={"Scheduled publishing"} close={@close}>
      <:info>
        <p>
          Set a future publishing date for this entry. Leave blank for immediate publishing.
        </p>
      </:info>
      <div class="brando-input">
        <Input.Datetime.render field={:publish_at} form={@form} />
      </div>
    </Content.drawer>
    """
  end
end
