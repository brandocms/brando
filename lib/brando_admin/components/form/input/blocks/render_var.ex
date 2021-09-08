defmodule BrandoAdmin.Components.Form.Input.RenderVar do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.Input

  prop var, :any
  prop render, :atom, values: [:all, :only_important, :only_regular], default: :all
  prop edit, :boolean, default: false

  data should_render?, :boolean
  data label, :string
  data type, :string

  def v(form, field) do
    input_value(form, field)
  end

  def update(%{var: var, render: render, edit: edit}, socket) do
    important = v(var, :important)

    should_render? =
      cond do
        render == :all -> true
        render == :only_important and important -> true
        render == :only_regular and !important -> true
        true -> false
      end

    {:ok,
     socket
     |> assign(:edit, edit)
     |> assign(:should_render?, should_render?)
     |> assign(:important, important)
     |> assign(:label, v(var, :label))
     |> assign(:type, v(var, :type))
     |> assign(:var, var)}
  end

  def render(assigns) do
    ~F"""
      <div>
        {#if @should_render?}
          {#if @edit}
            <div id={"#{@var.id}-edit"}>
              <h2><code>{input_value(@var, :key)}</code></h2>
              <Input.Toggle form={@var} field={:marked_as_deleted} />
              <Input.Toggle form={@var} field={:important} />
              <Input.Text form={@var} field={:key} />
              <Input.Text form={@var} field={:label} />
              <Input.Radios form={@var} field={:type} options={[
                %{label: "Boolean", value: "boolean"},
                %{label: "Color", value: "color"},
                %{label: "Datetime", value: "datetime"},
                %{label: "Html", value: "html"},
                %{label: "String", value: "string"},
                %{label: "Text", value: "text"}
              ]} />
              {hidden_input @var, :value}
            </div>
          {#else}
            <div id={"#{@var.id}-value"}>
              {hidden_input @var, :key}
              {hidden_input @var, :label}
              {hidden_input @var, :type}
              {hidden_input @var, :important}

              <div class="brando-input">
                {#case @type}
                  {#match "string"}
                    <Input.Text form={@var} field={:value} label={@label} />

                  {#match "text"}
                    <Input.Textarea form={@var} field={:value} label={@label} />

                  {#match "boolean"}
                    <Input.Toggle form={@var} field={:value} label={@label} />

                  {#match "color"}
                    <Input.Text form={@var} field={:value} label={@label} />

                  {#match "datetime"}
                    <Input.Datetime form={@var} field={:value} label={@label} />

                  {#match "html"}
                    <Input.RichText form={@var} field={:value} label={@label} />
                {/case}
              </div>
            </div>
          {/if}
        {/if}
      </div>
    """
  end
end
