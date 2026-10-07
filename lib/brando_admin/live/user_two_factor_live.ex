defmodule BrandoAdmin.UserTwoFactorLive do
  @moduledoc false
  # The second step of a sign-in: the password was right, and the user gives
  # a passkey, a code from their authenticator app or a recovery code. The
  # forms post to `BrandoAdmin.UserSessionController` (`passkey/2` and
  # `two_factor/2`), which check them and log the user in; this screen only
  # asks. It is in the user's own language, since the password told us who
  # they are.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias Brando.Users.Passkeys
  alias Brando.Users.TwoFactor
  alias BrandoAdmin.Components.Auth
  alias Phoenix.Flash

  def render(assigns) do
    ~H"""
    <Auth.shell>
      <div id="two_factor" class="login-two-factor">
        <Auth.title subtitle={gettext("Two-factor authentication")} />
        <Auth.notice kind={:error} message={@error_message} />

        <div :if={@passkeys?} class="login-passkey">
          <p class="login-intro">{gettext("Confirm with your passkey: your fingerprint, face, PIN or security key.")}</p>
          <.form for={%{}} id="passkey_form" action="/admin/login/passkey" phx-update="ignore">
            <input
              :for={field <- ~w(id authenticator_data signature client_data_json user_handle)}
              type="hidden"
              name={"passkey[#{field}]"}
            />
            <p class="login-passkey-error" data-passkey-error hidden>
              {gettext("No passkey was used. Try again, or use another way below.")}
            </p>
          </.form>
          <div class="login-actions">
            <button
              type="button"
              id="two-factor-passkey"
              class="primary"
              phx-hook="Brando.Passkey"
              data-passkey="login"
              data-mode="second_factor"
              data-options-url="/admin/login/passkey/options"
              data-form="#passkey_form"
              data-testid="two-factor-passkey"
            >
              {gettext("Use a passkey")}
            </button>
          </div>
        </div>

        <.form
          for={@form}
          id="two_factor_form"
          action="/admin/login/two-factor"
          phx-update="ignore"
          class={[@passkeys? && "login-two-factor-alternative"]}
        >
          <%= if @totp? do %>
            <p class="login-intro">
              {if @passkeys?,
                do: gettext("Or enter the 6-digit code from your authenticator app."),
                else:
                  gettext("Open your authenticator app and enter the 6-digit code it shows for %{email}.",
                    email: @email
                  )}
            </p>
            <.code_field form={@form} label={gettext("Code")} />
            <details class="login-recovery">
              <summary>{gettext("Lost your phone?")}</summary>
              <p>
                {gettext(
                  "Enter one of the recovery codes you saved when you set up two-factor authentication, in the field above. Each code works once. If you have none left, ask an administrator to reset two-factor authentication for you."
                )}
              </p>
            </details>
            <div class="login-actions">
              <button
                class={[!@passkeys? && "primary"]}
                phx-disable-with={gettext("Checking...")}
                data-testid="two-factor-submit"
              >
                {gettext("Verify")}
              </button>
              <.link href="/admin/logout" class="login-link">{gettext("Back to login")}</.link>
            </div>
          <% else %>
            <details class="login-recovery">
              <summary>{gettext("Lost your passkey?")}</summary>
              <p>
                {gettext(
                  "Enter one of the recovery codes you saved when you added your first passkey. Each code works once. If you have none left, ask an administrator to reset two-factor authentication for you."
                )}
              </p>
              <.code_field form={@form} label={gettext("Recovery code")} />
              <div class="login-actions">
                <button phx-disable-with={gettext("Checking...")} data-testid="two-factor-submit">{gettext("Verify")}</button>
              </div>
            </details>
            <div class="login-actions">
              <.link href="/admin/logout" class="login-link">{gettext("Back to login")}</.link>
            </div>
          <% end %>
        </.form>
      </div>
    </Auth.shell>
    """
  end

  attr :form, :any, required: true
  attr :label, :string, required: true

  defp code_field(assigns) do
    ~H"""
    <div class="field-wrapper">
      <Auth.input
        field={@form[:code]}
        label={@label}
        autocomplete="one-time-code"
        inputmode="numeric"
        spellcheck="false"
        autocapitalize="off"
        data-testid="two-factor-code"
        required
        autofocus
      />
    </div>
    """
  end

  def mount(_params, session, socket) do
    case Users.get_pending_login(session["pending_login_token"]) do
      {user, :pending} ->
        Auth.put_locale(user.language)

        {:ok,
         assign(socket,
           email: user.email,
           totp?: TwoFactor.totp_enabled?(user),
           passkeys?: Passkeys.any?(user),
           form: to_form(%{"code" => ""}, as: "two_factor"),
           error_message: Flash.get(socket.assigns.flash, :error),
           page_title: gettext("Two-factor authentication")
         )}

      {_user, :verified} ->
        {:ok, push_navigate(socket, to: "/admin/login/two-factor/setup")}

      nil ->
        Auth.put_locale()

        {:ok,
         socket
         |> put_flash(:error, gettext("Your login took too long. Log in again."))
         |> push_navigate(to: "/admin/login")}
    end
  end
end
