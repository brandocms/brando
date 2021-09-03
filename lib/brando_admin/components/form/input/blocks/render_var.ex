defmodule BrandoAdmin.Components.Form.Input.Blocks.RenderVar do
  use Surface.Component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input

  prop var, :any
  prop important, :boolean, default: false

  data should_render?, :boolean
  data label, :string
  data type, :string

  def v(form, field) do
    input_value(form, field)
  end

  def update(%{var: var, important: render_important}, socket) do
    important = v(var, :important)

    should_render? =
      cond do
        render_important and important -> true
        render_important and !important -> false
        true -> true
      end

    {:ok,
     socket
     |> assign(:should_render?, should_render?)
     |> assign(:important, important)
     |> assign(:label, v(var, :label))
     |> assign(:type, v(var, :type))
     |> assign(:var, var)}
  end

  def render(assigns) do
    ~F"""
      {#if @should_render?}
        {hidden_input @var, :name}
        {hidden_input @var, :label}
        {hidden_input @var, :type}
        {hidden_input @var, :important}

        {#case @type}
          {#match :string}
            <Input.Text form={@var} field={:value} label={@label} />

          {#match :text}
            <Input.Textarea form={@var} field={:value} label={@label} />

          {#match :boolean}
            <Input.Toggle form={@var} field={:value} label={@label} />

          {#match :color}
            <Input.Text form={@var} field={:value} label={@label} />
        {/case}
      {/if}
    """
  end
end
