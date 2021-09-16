defmodule BrandoAdmin.Components.Form.Input.RichText do
  use Surface.Component
  # use Phoenix.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase

  prop form, :form
  prop field, :any
  prop blueprint, :any
  prop input, :any
  prop label, :string
  prop value, :any
  prop placeholder, :string
  prop instructions, :string
  prop class, :string

  data initial_props, :map

  def update(%{form: form, input: %{name: name}} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:initial_props, fn ->
       Jason.encode!(%{content: v(form, name)})
     end)}
  end

  def update(%{form: form, field: field} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:initial_props, fn ->
       Jason.encode!(%{content: v(form, field)})
     end)}
  end

  def update(%{value: value} = assigns, socket) do
    require Logger
    Logger.error("==> update rich_text value: #{inspect(value, pretty: true)}")

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:initial_props, fn ->
       Jason.encode!(%{content: value})
     end)}
  end

  def v(form, field), do: Ecto.Changeset.get_field(form.source, field)

  def render(%{blueprint: _, input: %{name: name, opts: opts}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      field={name}
      class={opts[:class]}
      form={@form}>
      {hidden_input @form, name, class: "tiptap-text", phx_debounce: 500}
      <div class="tiptap-wrapper" id={"#{@form.id}-#{name}-rich-text-wrapper"}>
        <div
          id={"#{@form.id}-#{name}-rich-text"}
          phx-hook="Brando.TipTap"
          data-name="TipTap"
          data-props={@initial_props}>
          <div
            id={"#{@form.id}-#{name}-rich-text-target-wrapper"}
            class="tiptap-target-wrapper"
            phx-update="ignore">
            <div
              id={"#{@form.id}-#{name}-rich-text-target"}
              class="tiptap-target">
            </div>
          </div>
        </div>
      </div>
    </FieldBase>
    """
  end

  def render(%{form: _form, field: _field} = assigns) do
    ~F"""
    <FieldBase
      class={@class}
      label={@label}
      placeholder={@placeholder}
      instructions={@instructions}
      field={@field}
      form={@form}>
      {hidden_input @form, @field, class: "tiptap-text", phx_debounce: 500}
      <div class="tiptap-wrapper" id={"#{@form.id}-#{@field}-rich-text-wrapper"}>
        <div
          id={"#{@form.id}-#{@field}-text"}
          phx-hook="Brando.TipTap"
          data-name="TipTap"
          data-props={@initial_props}>
          <div
            id={"#{@form.id}-#{@field}-text-target-wrapper"}
            class="tiptap-target-wrapper"
            phx-update="ignore">
            <div class="tiptap-target" id={"#{@form.id}-#{@field}-text-target"}>
            </div>
          </div>
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
      {hidden_input @form, @field, value: @value, class: "tiptap-text", phx_debounce: 500}
      <div class="tiptap-wrapper" id={"#{@form.id}-#{@field}-rich-text-wrapper"}>
        <div
          id={"#{@form.id}-#{@field}-text"}
          phx-hook="Brando.TipTap"
          data-name="TipTap"
          data-props={@initial_props}>
          <div
            id={"#{@form.id}-#{@field}-text-target-wrapper"}
            class="tiptap-target-wrapper"
            phx-update="ignore">
            <div class="tiptap-target" id={"#{@form.id}-#{@field}-text-target"}>
            </div>
          </div>
        </div>
      </div>
    </FieldBase>
    """
  end
end
