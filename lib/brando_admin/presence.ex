defmodule BrandoAdmin.Presence do
  @moduledoc """
  Progress sent through user channel
  """

  defmacro __using__(_) do
    quote do
      def handle_info(
            %{event: "presence_diff", payload: %{joins: joins, leaves: leaves}},
            socket
          ) do
        {:noreply, push_event(socket, "b:presence:diff", %{joins: joins, leaves: leaves})}
      end
    end
  end
end
