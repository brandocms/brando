defmodule BrandoAdmin.Components.Form.Fieldset.Field do
  use BrandoAdmin, :component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input
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
    translations =
      case assigns.input.__struct__ do
        Brando.Blueprint.Form.Subform ->
          get_in(assigns.translations, [:fields, assigns.input.field]) || []

        Brando.Blueprint.Form.Input ->
          get_in(assigns.translations, [:fields, assigns.input.name]) || []
      end

    label = Keyword.get(translations, :label)
    placeholder = Keyword.get(translations, :placeholder)

    instructions =
      case Keyword.get(translations, :instructions) do
        nil -> nil
        val -> raw(val)
      end

    assigns =
      assigns
      |> assign(:label, label)
      |> assign(:instructions, instructions)
      |> assign(:placeholder, placeholder)

    ~H"""
    <%= if @input.__struct__ == Brando.Blueprint.Form.Subform do %>
      <%= if @input.component do %>
        <.live_component module={@input.component}
          id={"#{@form.id}-#{@input.field}-custom-component"}
          form={@form}
          label={@label}
          instructions={@instructions}
          placeholder={@placeholder}
          subform={@input}
          uploads={@uploads}
          current_user={@current_user}
          opts={[]} />
      <% else %>
        <.live_component module={Subform}
          id={"#{@form.id}-subform-#{@input.field}"}
          form={@form}
          uploads={@uploads}
          subform={@input}
          label={@label}
          instructions={@instructions}
          placeholder={@placeholder}
          current_user={@current_user} />
      <% end %>
    <% else %>
      <Input.render
        id={"#{@form.id}-#{@input.name}"}
        form={@form}
        field={@input.name}
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
