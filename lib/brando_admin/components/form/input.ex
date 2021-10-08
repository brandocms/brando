defmodule BrandoAdmin.Components.Form.Input do
  use Surface.LiveComponent
  use Phoenix.HTML

  prop current_user, :any
  prop form, :any
  prop input, :any
  prop blueprint, :any
  prop uploads, :any

  data component_module, :any
  data component_opts, :any
  data component_id, :string

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    component_module =
      case assigns.input.type do
        {:component, module} ->
          module

        type ->
          input_type = type |> to_string |> Recase.to_pascal()
          Module.concat([__MODULE__, input_type])
      end

    component_id =
      Enum.join(
        [assigns.form.id, assigns.input.name],
        "-"
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:component_id, component_id)
     |> assign(:component_module, component_module)
     |> assign(:component_opts, assigns.input.opts)}
  end

  def render(assigns) do
    ~F"""
    <div class="brando-input">
      {live_component(@socket, @component_module,
        id: @component_id,
        form: @form,
        input: @input,
        blueprint: @blueprint,
        uploads: @uploads,
        opts: @component_opts,
        current_user: @current_user
      )}
    </div>
    """
  end
end
