defmodule BrandoAdmin.UserLoginLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Auth
  alias Phoenix.Flash

  def render(assigns) do
    ~H"""
    <Auth.shell>
      <.form for={@form} id="login_form" action={@create_action} phx-update="ignore" as={:user}>
        <Auth.title />
        <Auth.notice kind={:error} message={@error_message} />
        <Auth.notice message={@info_message} />

        <div class="field-wrapper">
          <Auth.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            data-testid="email"
            autofocus
          />
        </div>

        <div class="field-wrapper">
          <Auth.input
            field={@form[:password]}
            label={gettext("Password")}
            type="password"
            autocomplete="current-password"
            data-testid="password"
          />
        </div>

        <div class="field-wrapper">
          <div class="check-wrapper small">
            <Auth.input field={@form[:remember_me]} type="checkbox" label={gettext("Keep me logged in for 60 days")} />
          </div>
        </div>
        <div class="login-actions">
          <button class="primary" phx-disable-with={gettext("Logging in...")} data-testid="login-button">
            {gettext("Log in")}
          </button>
          <.link navigate="/admin/reset-password" class="login-link" data-testid="forgot-password">
            {gettext("Forgot password?")}
          </.link>
        </div>
      </.form>
    </Auth.shell>
    """
  end

  def mount(_params, _session, socket) do
    Auth.put_locale()
    email = Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       form: form,
       create_action: "/admin/login",
       error_message: Flash.get(socket.assigns.flash, :error),
       info_message: Flash.get(socket.assigns.flash, :info)
     ), temporary_assigns: [form: form]}
  end
end
