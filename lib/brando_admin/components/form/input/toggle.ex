defmodule BrandoAdmin.Components.Form.Input.Toggle do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Label

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop name, :any
  prop label, :string
  prop placeholder, :string
  prop instructions, :string
  prop class, :any
  prop small, :boolean

  data field_name, :any
  data classes, :string
  data text, :string
  data small?, :boolean

  slot default

  def update(%{input: %{name: name, opts: opts}} = assigns, socket) do
    {:ok,
     socket
     |> assign(:classes, opts[:class])
     |> assign(:small?, Keyword.get(opts, :small, false))
     |> assign(:field_name, name)
     |> assign(assigns)}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  def render(%{blueprint: nil} = assigns) do
    ~F"""
    <FieldBase
      label={@label}
      placeholder={@placeholder}
      instructions={@instructions}
      field={@field}
      form={@form}>
      <Label form={@form} field={@field} class={"switch", small: @small}>
        {#if slot_assigned?(:default)}
          <#slot />
        {#else}
          {checkbox @form, @field}
        {/if}
        <div class="slider round"></div>
      </Label>
    </FieldBase>
    """
  end

  def render(%{blueprint: _} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={@field_name}
      class={@classes}
      form={@form}>
      <Label form={@form} field={@field_name} class={"switch", small: @small?}>
        {#if slot_assigned?(:default)}
          <#slot />
        {#else}
          {checkbox @form, @field_name}
        {/if}
        <div class="slider round"></div>
      </Label>
    </FieldBase>
    """
  end
end
