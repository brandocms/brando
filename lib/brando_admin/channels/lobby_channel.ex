defmodule Brando.LobbyChannel do
  @moduledoc "Workspace-aware activity tracking and administration notifications."
  use Phoenix.Channel
  alias Brando.Authorization.{Engine, Realtime, Scope}

  # Phoenix broadcasts tracker diffs on the channel topic. Clients do not use
  # these; only the authorized Chrome LiveView renders presence information.
  intercept(["presence_diff", "toast"])

  def join("lobby", %{"url" => url} = params, socket) when is_binary(url) do
    Realtime.allow_sandbox(socket)

    with {:ok, scope} <- resolve_scope(params["scope_token"], socket.assigns.user_id) do
      Realtime.subscribe()
      send(self(), :after_join)
      {:ok, %{}, socket |> assign(:url, URI.parse(url).path) |> assign(:scope, scope)}
    else
      _ -> {:error, %{reason: "forbidden"}}
    end
  end

  def join(_, _, _), do: {:error, %{reason: "forbidden"}}

  def handle_in("user:state", %{"active" => active}, socket) when is_boolean(active) do
    update_presence(socket, &%{&1 | online_at: timestamp(), active: active})
  end

  def handle_in("user:state", %{"url" => url}, socket) when is_binary(url) do
    update_presence(socket, &%{&1 | online_at: timestamp(), url: URI.parse(url).path})
  end

  def handle_in(_, _, socket), do: {:reply, {:error, %{reason: "invalid_state"}}, socket}

  def handle_info(:after_join, socket) do
    if Realtime.authorize_scope(socket.assigns.scope) == :ok do
      {:ok, _} =
        Brando.presence().track(socket, socket.assigns.user_id, %{
          online_at: timestamp(),
          active: true,
          url: socket.assigns.url,
          scope: socket.assigns.scope
        })

      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  def handle_info({:authorization_changed, _}, socket) do
    if Realtime.authorize_scope(socket.assigns.scope) == :ok,
      do: {:noreply, socket},
      else: {:stop, :normal, socket}
  end

  def handle_out("presence_diff", _payload, socket), do: {:noreply, socket}

  def handle_out("toast", payload, socket) do
    if Realtime.notification_allowed?(socket.assigns.scope, payload),
      do: push(socket, "toast", Map.delete(payload, :authorization))

    {:noreply, socket}
  end

  defp update_presence(socket, fun) do
    if Realtime.authorize_scope(socket.assigns.scope) == :ok do
      Brando.presence().update(socket, socket.assigns.user_id, fun)
      {:reply, :ok, socket}
    else
      {:stop, :normal, socket}
    end
  end

  defp resolve_scope(nil, id) do
    if not Engine.enabled?() and Brando.Tenant.mode() == :none and Realtime.authorize_account(id) == :ok,
      do: {:ok, Scope.standalone(%{id: id})},
      else: {:error, :forbidden}
  end

  defp resolve_scope(token, id), do: Realtime.verify_scope(token, id)
  defp timestamp, do: to_string(System.system_time(:second))
end
