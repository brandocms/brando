defmodule BrandoAdmin.Components.Form.Input.Code do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias Surface.Components.Form.HiddenInput
  alias Surface.Components.Form.TextArea

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop value, :any
  prop placeholder, :string
  prop instructions, :string

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  def render(%{blueprint: _, input: %{name: name, opts: opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      form={@form}>
      <div
        id={"#{@form.id}-#{name}-code"}
        class="code-editor"
        phx-hook="Brando.CodeEditor">
          <div phx-update="ignore">
            <TextArea
              form={@form}
              field={name} />

            <div class="editor"></div>
          </div>
      </div>
    </FieldBase>
    """
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      field={@field}
      form={@form}>
      <div
        id={"#{@form.id}-#{@field}-code"}
        class="code-editor"
        phx-hook="Brando.CodeEditor">
          <div phx-update="ignore">
            <TextArea
              form={@form}
              field={@field}
              value={@value} />

            <div class="editor"></div>
          </div>
      </div>
    </FieldBase>
    """
  end
end
