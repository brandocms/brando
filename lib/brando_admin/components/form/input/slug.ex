defmodule BrandoAdmin.Components.Form.Input.Slug do
  use Surface.Component
  # use Phoenix.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias Surface.Components.Form.TextInput

  prop form, :form
  prop blueprint, :any

  data name, :any
  data class, :string
  data slug_for, :string

  def update(%{input: %{name: name, opts: opts}} = assigns, socket) do
    {:ok,
     socket
     |> assign(:class, opts[:class])
     |> assign(:slug_for, opts[:for])
     |> assign(:name, name)
     |> assign(assigns)}
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={@name}
      class={@class}
      form={@form}>
      <TextInput
        form={@form}
        field={@name}
        class={"text monospace"}
        opts={
          phx_hook: "Brando.Slug",
          phx_debounce: 750,
          data_slug_for: "#{@form.id}_#{@slug_for}",
          autocorrect: "off",
          spellcheck: "false"}
        />
    </FieldBase>
    """
  end
end
