defmodule Brando.SystemChannel do
  @moduledoc """
  Channel for system information.
  """

  use Phoenix.Channel

  intercept([
    "log_msg",
    "alert",
    "set_progress",
    "increase_progress"
  ])

  def join("system:stream", _auth_msg, socket) do
    {:ok, socket}
  end

  def join("system:" <> _private_room_id, _auth_msg, _socket) do
    :ignore
  end

  def handle_out("log_msg", payload, socket) do
    push(socket, "log_msg", payload)
    {:noreply, socket}
  end

  def handle_out("alert", payload, socket) do
    push(socket, "alert", payload)
    {:noreply, socket}
  end

  def handle_out("set_progress", payload, socket) do
    push(socket, "set_progress", payload)
    {:noreply, socket}
  end

  def handle_out("increase_progress", payload, socket) do
    push(socket, "increase_progress", payload)
    {:noreply, socket}
  end

  @doc """
  Log different events
  """
  def log(:logged_in, user) do
    body = "#{user.full_name} logget inn"
    do_log(:notice, "fa-info-circle", body)
  end

  def log(:logged_out, user) do
    body = "#{user.full_name} logget ut"
    do_log(:notice, "fa-info-circle", body)
  end

  def log(:error, message) do
    do_log(:error, "fa-times-circle", message)
  end

  def log(:info, message) do
    do_log(:info, "fa-info-circle", message)
  end

  defp do_log(level, icon, body) do
    unless Brando.config(:logging)[:disable_logging] do
      Brando.endpoint().broadcast!("system:stream", "log_msg", %{
        level: level,
        icon: icon,
        body: body
      })
    end
  end

  def alert(message) do
    unless Brando.config(:logging)[:disable_logging] do
      Brando.endpoint().broadcast!("system:stream", "alert", %{message: message})
    end
  end

  def set_progress(value) do
    Brando.endpoint().broadcast!("system:stream", "set_progress", %{value: value})
  end

  def increase_progress(value) do
    Brando.endpoint().broadcast!("system:stream", "increase_progress", %{value: value})
  end

  def popup_form(header, form, opts) do
    form = form.get_popup_form(opts)

    Brando.endpoint().broadcast!("system:stream", "popup_form", %{
      form: Phoenix.HTML.safe_to_string(form.rendered_form),
      url: form.url,
      header: header
    })
  end
end
