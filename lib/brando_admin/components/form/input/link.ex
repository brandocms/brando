defmodule BrandoAdmin.Components.Form.Input.Link do
  @moduledoc false
  use BrandoAdmin, :live_component

  alias BrandoAdmin.Components.Form.Input.RenderVar

  # prop form, :form
  # prop subform, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> ensure_default_link()}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.inputs_for :let={var} field={@field}>
        <.live_component
          module={RenderVar}
          id={"#{@field.id}-render-var-#{var.index}"}
          var={var}
          render={:all}
        />
      </.inputs_for>
    </div>
    """
  end

  def ensure_default_link(socket) do
    field = socket.assigns.field
    changeset = field.form.source

    field_name = field.field
    current_link = Ecto.Changeset.get_field(changeset, field_name)

    if current_link do
      socket
    else
      default_link =
        %Brando.Content.Var{}
        |> Ecto.Changeset.change(%{
          type: :link,
          label: "Link",
          key: "link",
          value: nil,
          important: true,
          link_type: :url
        })
        |> Map.put(:action, :insert)

      module = changeset.data.__struct__
      form_id = "#{module.__naming__().singular}_form"

      updated_changeset = Ecto.Changeset.put_change(changeset, field_name, default_link)

      send_update(BrandoAdmin.Components.Form,
        id: form_id,
        action: :update_changeset,
        changeset: updated_changeset
      )

      socket
    end
  end
end
