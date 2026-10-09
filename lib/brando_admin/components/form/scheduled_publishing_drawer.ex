defmodule BrandoAdmin.Components.Form.ScheduledPublishingDrawer do
  @moduledoc false
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
    <Content.drawer
      id={@id}
      title={gettext("Scheduled publishing")}
      close={@close}
      icon="calendar-days"
      workspace
      editor
      narrow
    >
      <:info>
        <p>
          {gettext("Set a future publishing date for this entry. Leave blank for immediate publishing.")}
        </p>
      </:info>
      <div class="brando-input">
        <Input.datetime
          field={@form[:publish_at]}
          label={gettext("Publish at")}
          instructions={publish_at_instructions(@form)}
        />
      </div>
      <div class="brando-input">
        <Input.datetime
          field={@form[:unpublish_at]}
          label={gettext("Expires")}
          instructions={gettext("The entry is deactivated at this time. Leave blank to keep it published.")}
        />
      </div>
    </Content.drawer>
    """
  end

  # The job publishes only a pending entry: a coming date on a draft does nothing
  defp publish_at_instructions(%{source: %Ecto.Changeset{} = changeset}) do
    status = to_string(Ecto.Changeset.get_field(changeset, :status))

    with true <- status in ["draft", "disabled"],
         %DateTime{} = publish_at <- Ecto.Changeset.get_field(changeset, :publish_at),
         true <- DateTime.after?(publish_at, DateTime.utc_now()) do
      gettext("Only a pending entry is published at this time. Set the status to Pending to schedule it.")
    else
      _ -> nil
    end
  end

  defp publish_at_instructions(_form), do: nil
end
