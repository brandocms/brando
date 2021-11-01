defmodule BrandoAdmin.Components.Form.Input do
  use BrandoAdmin, :component
  use Phoenix.HTML

  # prop current_user, :any
  # prop form, :any
  # prop field, :any
  # prop label, :any
  # prop placeholder, :any
  # prop instructions, :any
  # prop opts, :list, default: []
  # prop uploads, :any
  # prop type, :any

  # data component_module, :any
  # data component_opts, :any
  # data component_id, :string

  def mount(socket) do
    {:ok, socket}
  end

  defp is_live?(module) do
    {:__live__, 0} in module.__info__(:functions)
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:component_id, fn ->
        Enum.join(
          [assigns.form.id, assigns.field],
          "-"
        )
      end)
      |> assign_new(:component_module, fn ->
        case assigns.type do
          {:component, module} ->
            module

          type ->
            input_type = type |> to_string |> Recase.to_pascal()
            Module.concat([__MODULE__, input_type])
        end
      end)

    if is_live?(assigns.component_module) do
      ~H"""
      <div class="brando-input">
        <.live_component
          module={@component_module}
          id={@component_id}
          form={@form}
          field={@field}
          label={@label}
          placeholder={@placeholder}
          instructions={@instructions}
          uploads={@uploads}
          opts={@opts}
          current_user={@current_user} />
      </div>
      """
    else
      apply(assigns.component_module, :render, List.wrap(assigns))
    end
  end
end
