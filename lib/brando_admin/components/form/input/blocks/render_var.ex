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
  data instructions, :string
  data placeholder, :string

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

    type = v(var, :type)
    value = v(var, :value)

    value = control_value(type, value)

    {:ok,
     socket
     |> assign(:edit, edit)
     |> assign(:should_render?, should_render?)
     |> assign(:important, important)
     |> assign(:label, v(var, :label))
     |> assign(:type, type)
     |> assign(:value, value)
     |> assign(:instructions, v(var, :instructions))
     |> assign(:placeholder, v(var, :placeholder))
     |> assign(:var, var)}
  end

  defp control_value("string", value) when is_binary(value), do: value
  defp control_value("string", _value), do: ""

  defp control_value("text", value) when is_binary(value), do: value
  defp control_value("text", _value), do: ""

  defp control_value("datetime", %DateTime{} = value), do: value
  defp control_value("datetime", %Date{} = value), do: value
  defp control_value("datetime", _value), do: DateTime.utc_now()

  defp control_value("boolean", value) when is_boolean(value), do: value
  defp control_value("boolean", _value), do: false

  defp control_value("color", "#" <> value), do: "##{value}"
  defp control_value("color", _value), do: "#000000"

  defp control_value("html", value) when is_binary(value), do: value
  defp control_value("html", _value), do: "<p></p>"

  def render(assigns) do
    ~F"""
      <div class={"variable", input_value(@var, :type)}>
        {#if @should_render?}
          {#if @edit}
            <div id={"#{@var.id}-edit"}>
              <h2><code>{input_value(@var, :key)}</code></h2>
              <Input.Toggle form={@var} field={:marked_as_deleted} />
              <Input.Toggle form={@var} field={:important} />
              <Input.Text form={@var} field={:key} />
              <Input.Text form={@var} field={:label} />
              <Input.Text form={@var} field={:instructions} />
              <Input.Text form={@var} field={:placeholder} />
              <Input.Radios form={@var} field={:type} options={[
                %{label: "Boolean", value: "boolean"},
                %{label: "Color", value: "color"},
                %{label: "Datetime", value: "datetime"},
                %{label: "Html", value: "html"},
                %{label: "String", value: "string"},
                %{label: "Text", value: "text"}
              ]} />
              {hidden_input @var, :value, value: @value}
            </div>
          {#else}
            <div id={"#{@var.id}-value"}>
              {hidden_input @var, :key}
              {hidden_input @var, :label}
              {hidden_input @var, :type}
              {hidden_input @var, :important}
              {hidden_input @var, :instructions}
              {hidden_input @var, :placeholder}

              <div class="brando-input">
                {#case @type}
                  {#match "string"}
                    <Input.Text form={@var} field={:value} label={@label} placeholder={@placeholder} instructions={@instructions} debounce={750} />

                  {#match "text"}
                    <Input.Textarea form={@var} field={:value} label={@label} placeholder={@placeholder} instructions={@instructions} debounce={750} />

                  {#match "boolean"}
                    <Input.Toggle form={@var} field={:value} label={@label} instructions={@instructions} />

                  {#match "color"}
                    <Input.Text form={@var} field={:value} label={@label} placeholder={@placeholder} instructions={@instructions} debounce={750} />

                  {#match "datetime"}
                    <Input.Datetime form={@var} field={:value} label={@label} instructions={@instructions} />

                  {#match "html"}
                    <Input.RichText form={@var} field={:value} label={@label} instructions={@instructions} />
                {/case}
              </div>
            </div>
          {/if}
        {/if}
      </div>
    """
  end
end
