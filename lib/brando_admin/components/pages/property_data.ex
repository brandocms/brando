defmodule BrandoAdmin.Components.Pages.PropertyData do
  use Surface.Component
  import Phoenix.HTML.Form
  alias BrandoAdmin.Components.Form.MapInputs
  alias BrandoAdmin.Components.Form.Input

  prop form, :any
  prop opts, :any

  def update(assigns, socket) do
    from_field = Keyword.fetch!(assigns.opts, :from)
    type = input_value(assigns.form, from_field)

    {:ok,
     socket
     |> assign(:form, assigns.form)
     |> assign(:type, type)}
  end

  def render(assigns) do
    ~F"""
    <MapInputs
      :let={value: value, subform: sform}
      form={@form}
      for={:data}>
      {#case @type}
        {#match "boolean"}
          <Input.Toggle form={sform} field={:value}>
            {checkbox sform, :value, value: value}
          </Input.Toggle>

        {#match "color"}
          <Input.Toggle form={sform} field={:value}>
            {checkbox sform, :value, value: value}
          </Input.Toggle>

        {#match "html"}
          <Input.RichText form={sform} field={:value} value={value} class="full" />

        {#match _}
          <Input.Text form={sform} field={:value} value={value} />
      {/case}
    </MapInputs>
    """
  end
end
