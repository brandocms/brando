defmodule Brando.SystemChannel do
  @moduledoc """
  Channel for system information.
  """
  @interval 1000

  use Phoenix.Channel
  import Brando.Gettext

  intercept [
    "log_msg",
    "alert",
    "set_progress",
    "increase_progress"
  ]

  def join("system:stream", _auth_msg, socket) do
    {:ok, socket}
  end

  def join("system:" <> _private_room_id, _auth_msg, _socket) do
    :ignore
  end

  def handle_out("log_msg", payload, socket) do
    push socket, "log_msg", payload
    {:noreply, socket}
  end

  def handle_out("alert", payload, socket) do
    push socket, "alert", payload
    {:noreply, socket}
  end

  def handle_out("set_progress", payload, socket) do
    push socket, "set_progress", payload
    {:noreply, socket}
  end

  def handle_out("increase_progress", payload, socket) do
    push socket, "increase_progress", payload
    {:noreply, socket}
  end

  def handle_in("popup_form:create", %{"key" => key, "language" => language, "params" => params,
                                       "initial_values" => initial_values}, socket) do
    Gettext.put_locale(Brando.Gettext, language)
    Brando.I18n.put_locale_for_all_modules(language)

    case Brando.PopupForm.Registry.get(key) do
      {:ok, {_, _, header, _}} ->
        case Brando.PopupForm.create(key, params, initial_values) do
          %Brando.Form{} = form ->
            push socket, "popup_form:reply:#{key}", %{
              rendered_form: Phoenix.HTML.safe_to_string(form.rendered_form),
              url: form.url,
              header: header
            }
          _ ->
            push socket, "popup_form:error:#{key}", %{
              message: gettext(~s(Error retrieving form "%{form}"), form: inspect(key))
            }
        end
      {:error, :not_registered} ->
        push socket, "popup_form:error:#{key}", %{
          message: gettext(~s(Error retrieving form "%{form}". Not registered.), form: inspect(key))
        }
    end

    {:noreply, socket}
  end

  def handle_in("popup_form:push_data", %{"key" => key, "data" => data}, socket) do
    {:ok, {_, _, header, _}} = Brando.PopupForm.Registry.get(key)

    case Brando.PopupForm.post(key, data, socket) do
      {:error, form} ->
        push socket, "popup_form:reply_errors:#{key}", %{
          rendered_form: Phoenix.HTML.safe_to_string(form.rendered_form),
          url: form.url,
          header: header
        }
      {:ok, {inserted_record, wanted_fields}} ->
        fields = Map.take(inserted_record, wanted_fields)
        push socket, "popup_form:success:#{key}", %{fields: fields}
    end
    {:noreply, socket}
  end

  @doc """
  Logs when `user` performs a successful login
  """
  def log(:logged_in, user) do
    body = "#{user.full_name} logget inn"
    do_log(:notice, "fa-info-circle", body)
  end

  @doc """
  Logs when `user` performs a successful logout
  """
  def log(:logged_out, user) do
    body = "#{user.full_name} logget ut"
    do_log(:notice, "fa-info-circle", body)
  end

  @doc """
  Logs system error
  """
  def log(:error, message) do
    do_log(:error, "fa-times-circle", message)
  end

  @doc """
  Logs system info
  """
  def log(:info, message) do
    do_log(:info, "fa-info-circle", message)
  end

  defp do_log(level, icon, body) do
    unless Brando.config(:logging)[:disable_logging] do
      Brando.endpoint.broadcast!("system:stream", "log_msg",
                                 %{level: level, icon: icon, body: body})
    end
  end

  def alert(message) do
    unless Brando.config(:logging)[:disable_logging] do
      Brando.endpoint.broadcast!("system:stream", "alert", %{message: message})
    end
  end

  def set_progress(value) do
    Brando.endpoint.broadcast!("system:stream", "set_progress", %{value: value})
  end

  def increase_progress(value) do
    Brando.endpoint.broadcast!("system:stream", "increase_progress", %{value: value})
  end

  def popup_form(header, form, opts) do
    form = form.get_popup_form(opts)

    Brando.endpoint.broadcast!("system:stream", "popup_form", %{
      form: Phoenix.HTML.safe_to_string(form.rendered_form),
      url: form.url,
      header: header
    })
  end
end
