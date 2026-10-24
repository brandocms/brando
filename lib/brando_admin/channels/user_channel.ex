defmodule BrandoAdmin.UserChannel do
  @moduledoc """
  Channel for user specific interaction.
  """

  use Phoenix.Channel
  alias Brando.Authorization.Realtime

  intercept([
    "alert",
    "progress_popup",
    "set_progress",
    "increase_progress",
    "toast",
    "progress:show",
    "progress:hide",
    "progress:update",
    "work"
  ])

  @doc """
  Join user channel for your user
  """
  def join("user:" <> user_id, _params, socket) do
    Realtime.allow_sandbox(socket)
    assigned_user_id = socket.assigns.user_id

    vsn =
      Brando.otp_app()
      |> Application.spec(:vsn)
      |> to_string()

    if to_string(assigned_user_id) == user_id and BrandoAdmin.AdminSocket.session_valid?(socket) and
         Realtime.authorize_account(assigned_user_id) == :ok do
      Realtime.subscribe()
      # The channel hears its topic only once join/3 has returned
      send(self(), :sync_work)
      {:ok, %{vsn: vsn}, socket}
    else
      # A bare :error crashed the join instead of refusing it
      {:error, %{reason: "forbidden"}}
    end
  end

  def handle_out(event, payload, socket) do
    if Realtime.authorize_account(socket.assigns.user_id) == :ok do
      push(socket, event, payload)
      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  # Running background work, so a new tab or a reload shows its toasts. Read
  # after the channel subscribed to its topic, so no report falls between.
  def handle_info(:sync_work, socket) do
    work = socket.assigns.user_id |> BrandoAdmin.Work.list() |> Enum.map(&BrandoAdmin.Work.to_payload/1)
    push(socket, "work:sync", %{work: work})
    {:noreply, socket}
  end

  def handle_info({:authorization_changed, _}, socket) do
    if Realtime.authorize_account(socket.assigns.user_id) == :ok,
      do: {:noreply, socket},
      else: {:stop, :normal, socket}
  end

  def handle_info({:user_update, _usr}, socket) do
    {:noreply, socket}
  end

  def alert(user, message) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "alert", %{
      message: message
    })
  end

  def set_progress(user, value) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "set_progress", %{
      value: value
    })
  end

  def increase_progress(user, value) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "increase_progress", %{
      value: value
    })
  end
end
