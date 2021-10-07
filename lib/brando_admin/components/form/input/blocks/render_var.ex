defmodule BrandoAdmin.Components.Form.Input.RenderVar do
  use Surface.LiveComponent
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
  data value, :any
  data visible, :boolean

  def v(form, field) do
    input_value(form, field)
  end

  def mount(socket) do
    {:ok, assign(socket, visible: false)}
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
              <div class="variable-header" :on-click="toggle_visible">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm-2.29-2.333A17.9 17.9 0 0 1 8.027 13H4.062a8.008 8.008 0 0 0 5.648 6.667zM10.03 13c.151 2.439.848 4.73 1.97 6.752A15.905 15.905 0 0 0 13.97 13h-3.94zm9.908 0h-3.965a17.9 17.9 0 0 1-1.683 6.667A8.008 8.008 0 0 0 19.938 13zM4.062 11h3.965A17.9 17.9 0 0 1 9.71 4.333 8.008 8.008 0 0 0 4.062 11zm5.969 0h3.938A15.905 15.905 0 0 0 12 4.248 15.905 15.905 0 0 0 10.03 11zm4.259-6.667A17.9 17.9 0 0 1 15.973 11h3.965a8.008 8.008 0 0 0-5.648-6.667z"/></svg>
                <div class="variable-key">
                  {input_value(@var, :key)}
                  <span>{input_value(@var, :type)}</span>
                </div>
              </div>

              <div class={"variable-content", hidden: !@visible}>
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

  def handle_event("toggle_visible", _, socket) do
    {:noreply, update(socket, :visible, &(!&1))}
  end
end
