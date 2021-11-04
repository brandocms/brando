defmodule BrandoAdmin.Utils do
  import Phoenix.LiveView

  def prepare_input_component(%{assigns: assigns} = socket) do
    require Logger
    Logger.error(inspect(socket, pretty: true))

    socket =
      socket
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)

    assign(socket,
      class: assigns.opts[:class],
      monospace: assigns.opts[:monospace] || false,
      disabled: assigns.opts[:disabled] || false,
      debounce: assigns.opts[:debounce] || 750,
      compact: assigns.opts[:compact]
    )
  end

  def prepare_input_component(assigns) do
    assigns =
      assigns
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:instructions, fn -> nil end)
      |> assign_new(:placeholder, fn -> nil end)

    assign(assigns,
      class: assigns.opts[:class],
      monospace: assigns.opts[:monospace] || false,
      disabled: assigns.opts[:disabled] || false,
      debounce: assigns.opts[:debounce] || 750,
      compact: assigns.opts[:compact]
    )
  end
end
