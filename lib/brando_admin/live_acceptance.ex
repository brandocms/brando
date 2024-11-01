defmodule BrandoAdmin.Mounts.LiveAcceptance do
  def on_mount({:default, _module}, _params, _session, socket) do
    %{assigns: %{phoenix_ecto_sandbox: metadata}} =
      Phoenix.Component.assign_new(socket, :phoenix_ecto_sandbox, fn ->
        if Phoenix.LiveView.connected?(socket) do
          Phoenix.LiveView.get_connect_info(socket, :user_agent)
        end
      end)

    if metadata do
      Phoenix.Ecto.SQL.Sandbox.allow(metadata, Ecto.Adapters.SQL.Sandbox)
    end

    {:cont, socket}
  end
end
