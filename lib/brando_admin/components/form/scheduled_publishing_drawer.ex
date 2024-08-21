defmodule BrandoAdmin.Components.Form.ScheduledPublishingDrawer do
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input

  # prop form, :form, required: true
  # prop blueprint, :any, required: true
  # prop status, :atom, default: :closed
  # prop close, :event

  def render(assigns) do
    ~H"""
    <Content.drawer id={@id} title={gettext("Scheduled publishing")} close={@close}>
      <:info>
        <p>
          <%= gettext(
            "Set a future publishing date for this entry. Leave blank for immediate publishing."
          ) %>
        </p>
      </:info>
      <div class="brando-input">
        <Input.datetime field={@form[:publish_at]} label={gettext("Publish at")} />
      </div>
    </Content.drawer>
    """
  end
end
