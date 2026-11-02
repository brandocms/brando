defmodule BrandoAdmin.Authorization.EventGuard do
  @moduledoc """
  Puts `BrandoAdmin.Authorization.Events` in front of a LiveComponent's
  `handle_event/3`. A LiveView's hook does not see a component's events, so
  `use BrandoAdmin, :live_component` wraps them when the component compiles.

  No aliases and no calls at compile time: this expands in every admin
  component, and an edge from here would pull them into one recompilation unit.
  """
  defmacro __before_compile__(env) do
    if Module.defines?(env.module, {:handle_event, 3}, :def) do
      quote do
        defoverridable handle_event: 3

        def handle_event(event, params, socket) do
          if BrandoAdmin.Authorization.Events.component_refused?(__MODULE__, event),
            do: {:noreply, BrandoAdmin.Authorization.Events.refuse(socket, __MODULE__, event)},
            else: super(event, params, socket)
        end

        @doc false
        def __event_guard__, do: true
      end
    end
  end
end
