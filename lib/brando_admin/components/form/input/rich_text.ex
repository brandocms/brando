defmodule BrandoAdmin.Components.Form.Input.RichText do
  use Surface.Component
  # use Phoenix.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias Surface.Components.Form.HiddenInput

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop value, :any
  prop placeholder, :string
  prop instructions, :string
  prop class, :string

  def mount(socket) do
    # TODO: Since we're calling this component through `live_component` we lose the default props.
    # When there is proper support for dynamic components in Surface, we can change this hopefully.
    {:ok, assign(socket, :value, nil)}
  end

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def render(%{blueprint: _, input: %{name: name, opts: opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      class={opts[:class]}
      form={@form}>
      <div class="tiptap-wrapper">
        <HiddenInput
          class="tiptap-text"
          form={@form}
          field={name}
          value={@value}
          opts={phx_debounce: 500}
        />
        <div
          id={"#{@form.id}-#{name}-text"}
          phx-update="ignore"
          phx-hook="Brando.TipTap"
          data-name="TipTap"
          data-props={Jason.encode!(%{content: @value || v(@form, name)})}>
        </div>
      </div>
    </FieldBase>
    """
  end

  def render(assigns) do
    ~F"""
    <FieldBase
      class={@class}
      label={@label}
      placeholder={@placeholder}
      instructions={@instructions}
      field={@field}
      form={@form}>
      <div class="tiptap-wrapper">
        <HiddenInput
          class="tiptap-text"
          form={@form}
          field={@field}
          value={@value}
          opts={phx_debounce: 500}
        />
        <div
          id={"#{@form.id}-#{@field}-text"}
          phx-update="ignore"
          phx-hook="Brando.Component"
          data-name="TipTap"
          data-props={Jason.encode!(%{content: @value || v(@form, @field)})}>
        </div>
      </div>
    </FieldBase>
    """
  end
end
