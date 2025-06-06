defmodule BrandoAdmin.Components.Form.Fieldset.Field do
  @moduledoc false
  use BrandoAdmin, :component
  # use Phoenix.HTML

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Subform

  # prop input, :map
  # prop form, :form
  # prop parent_uploads, :any
  # prop current_user, :any

  # data label, :string
  # data instructions, :string
  # data placeholder, :string

  def render(assigns) do
    assigns =
      assigns
      |> assign(:label, nil)
      |> assign(:instructions, nil)
      |> assign(:placeholder, nil)
      |> assign_new(:form_cid, fn -> nil end)

    ~H"""
    <%= if @input.__struct__ == Brando.Blueprint.Forms.Subform do %>
      <%= if @input.component do %>
        <.live_component
          module={@input.component}
          id={"#{@form.id}-#{@input.name}-custom-component"}
          field={@form[@input.name]}
          label={@label}
          instructions={@instructions}
          placeholder={@placeholder}
          subform={@input}
          parent_uploads={@parent_uploads}
          current_user={@current_user}
          form_cid={@form_cid}
          opts={[]}
        />
      <% else %>
        <.live_component
          module={Subform}
          id={"#{@form.id}-subform-#{@input.name}"}
          field={@form[@input.name]}
          parent_uploads={@parent_uploads}
          subform={@input}
          label={@label}
          relations={@relations}
          instructions={@instructions}
          placeholder={@placeholder}
          current_user={@current_user}
          form_cid={@form_cid}
        />
      <% end %>
    <% else %>
      <Form.input
        field={@form[@input.name]}
        label={@label}
        instructions={@instructions}
        placeholder={@placeholder}
        parent_uploads={@parent_uploads}
        opts={@input.opts || []}
        type={@input.type}
        current_user={@current_user}
        form_cid={@form_cid}
        target={@form_cid}
      />
    <% end %>
    """
  end
end
