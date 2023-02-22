defmodule BrandoAdmin.Components.Form.Fieldset.Field do
  use BrandoAdmin, :component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Subform

  # prop input, :map
  # prop form, :form
  # prop uploads, :any
  # prop current_user, :any
  # prop translations, :any

  # data label, :string
  # data instructions, :string
  # data placeholder, :string

  def render(assigns) do
    assigns =
      assigns
      |> assign(:label, nil)
      |> assign(:instructions, nil)
      |> assign(:placeholder, nil)

    ~H"""
    <%= if @input.__struct__ == Brando.Blueprint.Forms.Subform do %>
      <%= if @input.component do %>
        <.live_component module={@input.component}
          id={"#{@form.id}-#{@input.name}-custom-component"}
          field={@form[@input.name]}
          label={@label}
          instructions={@instructions}
          placeholder={@placeholder}
          subform={@input}
          uploads={@uploads}
          current_user={@current_user}
          opts={[]} />
      <% else %>
        <.live_component module={Subform}
          id={"#{@form.id}-subform-#{@input.name}"}
          field={@form[@input.name]}
          uploads={@uploads}
          subform={@input}
          label={@label}
          relations={@relations}
          instructions={@instructions}
          placeholder={@placeholder}
          current_user={@current_user} />
      <% end %>
    <% else %>
      <Form.input
        field={@form[@input.name]}
        label={@label}
        instructions={@instructions}
        placeholder={@placeholder}
        uploads={@uploads}
        opts={@input.opts || []}
        type={@input.type}
        current_user={@current_user} />
    <% end %>
    """
  end
end
