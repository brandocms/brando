defmodule BrandoAdmin.Components.Form.ScheduledPublishingDrawer do
  use BrandoAdmin, :live_component
  alias BrandoAdmin.Components.Form.Input

  # prop form, :form, required: true
  # prop blueprint, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  def render(assigns) do
    ~H"""
    <div class={render_classes([drawer: true, "scheduled-publishing-drawer": true, open: @status == :open])}>
      <div class="inner">
        <div class="drawer-header">
          <h2>
            Scheduled publishing
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
            Set a future publishing date for this entry. Leave blank for immediate publishing.
          </p>
        </div>
        <div class="drawer-form">
          <div class="brando-input">
            <Input.Datetime.render field={:publish_at} form={@form} />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
