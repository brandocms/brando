defmodule BrandoAdmin.Reauth do
  @moduledoc """
  Asks for the password, a code from the authenticator app or a passkey
  again before a sensitive action, when the session last gave one more than
  a few minutes ago — even inside a valid session. A stolen session cookie
  then cannot change a password, add a passkey, create users, delete a site
  or set an environment live.

  When a session last confirmed is kept with the session itself, in
  `users_tokens.confirmed_at`: logging in sets it, and so does answering the
  prompt. (A LiveView cannot write the signed cookie session, so the
  timestamp lives with the session's server-side record.) The window is ten
  minutes:

      config :brando, BrandoAdmin.Reauth, window_minutes: 10

  ## Screens and actions opt in with one line

  A whole screen — every visit to it asks first, when the session has not
  confirmed lately, and comes back after; once open, every event of the
  LiveView is held until the user confirms again, and the screen is left for
  the confirm page when the confirmation runs out:

      on_mount {BrandoAdmin.Reauth, :screen}

  Some events of a LiveView — the event is held while the prompt asks, and
  runs once it is answered:

      on_mount {BrandoAdmin.Reauth, events: ~w(delete_environment queue_set_live)}

  Events of a LiveComponent do not reach the LiveView's hooks. A screen
  guarded as a whole covers them by leaving when the confirmation runs out;
  otherwise guard an event of the LiveView that opens the component.

  A controller route uses the plug, which sends the user to confirm and back
  (for a GET; a form post is sent back to the page it came from):

      plug :require_recent_auth

  The prompt is rendered by the admin layout from the `:reauth` assign.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, push_navigate: 2, redirect: 2]

  alias Brando.Users
  alias Brando.Users.Passkeys
  alias Brando.Users.SecurityLog
  alias Brando.Users.Throttle
  alias Brando.Users.TwoFactor
  alias BrandoAdmin.Components.Auth
  alias BrandoAdmin.Components.Content
  alias Phoenix.LiveView.JS
  alias Plug.Conn

  @doc "How long a confirmation lasts, in seconds."
  @spec window_seconds() :: pos_integer()
  def window_seconds, do: ((Brando.config(__MODULE__) || [])[:window_minutes] || 10) * 60

  @doc "Whether the session (its token, or its token row's id) confirmed within the window."
  @spec fresh?(binary() | integer() | nil) :: boolean()
  def fresh?(token), do: Users.session_confirmed_within?(token, window_seconds())

  @doc "Where to confirm, coming back to `return_to` after."
  @spec confirm_path(String.t()) :: String.t()
  def confirm_path(return_to), do: "/admin/confirm?" <> URI.encode_query(%{"return_to" => return_to})

  ## Plug

  @doc "A plug for controller routes: sends a session that has not confirmed lately to confirm first."
  def require_recent_auth(conn, _opts) do
    if fresh?(Conn.get_session(conn, :user_token)) do
      conn
    else
      return_to =
        if conn.method == "GET",
          do: local_path(Phoenix.Controller.current_path(conn)),
          else: conn |> Conn.get_req_header("referer") |> List.first() |> local_path()

      conn
      |> Phoenix.Controller.redirect(to: confirm_path(return_to))
      |> Conn.halt()
    end
  end

  @doc """
  An admin path from `return_to`, or `/admin`: never another site, so the
  confirm page cannot send anyone elsewhere.
  """
  @spec local_path(String.t() | nil) :: String.t()
  def local_path(return_to) when is_binary(return_to) do
    case URI.parse(return_to) do
      %URI{path: "/admin" <> _ = path, query: nil} -> path
      %URI{path: "/admin" <> _ = path, query: query} -> path <> "?" <> query
      _ -> "/admin"
    end
  end

  def local_path(_), do: "/admin"

  ## on_mount

  def on_mount(:screen, _params, session, socket) do
    session_id = Users.token_id(session["user_token"])

    socket =
      socket
      |> setup(session_id, :all)
      |> attach_hook(:brando_reauth_uri, :handle_params, fn _params, uri, socket ->
        {:cont, Phoenix.Component.assign(socket, :reauth_return_to, local_path(uri))}
      end)

    if fresh?(session_id) do
      {:cont, schedule_expiry(socket, session_id)}
    else
      {:cont,
       attach_hook(socket, :brando_reauth_screen, :handle_params, fn _params, uri, socket ->
         {:halt, redirect(socket, to: confirm_path(local_path(uri)))}
       end)}
    end
  end

  def on_mount(opts, _params, session, socket) when is_list(opts) do
    session_id = Users.token_id(session["user_token"])

    socket =
      socket
      |> Phoenix.Component.assign(:reauth, Keyword.get(opts, :prompt))
      |> setup(session_id, Keyword.get(opts, :events, []))

    {:cont, socket}
  end

  # The session is kept by its token row's id, so the token itself stays out
  # of the LiveView's state.
  defp setup(socket, session_id, events) do
    socket
    |> Phoenix.Component.assign_new(:reauth, fn -> nil end)
    |> Phoenix.Component.assign(:reauth_meta, SecurityLog.socket_meta(socket))
    |> attach_hook(:brando_reauth, :handle_event, fn event, params, socket ->
      handle_event(event, params, socket, events, session_id)
    end)
  end

  # A screen opened while confirmed is left when the confirmation runs out,
  # so that a socket held open cannot outlast it; the confirm page brings the
  # user back. Every event is checked as well (see `handle_event/5`).
  defp schedule_expiry(socket, session_id) do
    if connected?(socket) do
      send_check(session_id)

      attach_hook(socket, :brando_reauth_expiry, :handle_info, fn
        {__MODULE__, :check, ^session_id}, socket -> {:halt, check_expiry(socket, session_id)}
        _message, socket -> {:cont, socket}
      end)
    else
      socket
    end
  end

  defp check_expiry(socket, session_id) do
    if fresh?(session_id) do
      send_check(session_id)
      socket
    else
      redirect(socket, to: confirm_path(socket.assigns[:reauth_return_to] || "/admin"))
    end
  end

  defp send_check(session_id) do
    remaining =
      case Users.session_confirmed_at(session_id) do
        nil -> 0
        at -> window_seconds() * 1000 - NaiveDateTime.diff(NaiveDateTime.utc_now(), at, :millisecond)
      end

    Process.send_after(self(), {__MODULE__, :check, session_id}, max(remaining, 0) + 500)
  end

  ## The prompt's events

  defp handle_event("brando:reauth:" <> action, params, socket, _events, session_id) do
    if socket.assigns[:reauth], do: prompt_event(action, params, socket, session_id), else: {:halt, socket}
  end

  defp handle_event(event, params, socket, events, session_id) do
    cond do
      events != :all and event not in events -> {:cont, socket}
      fresh?(session_id) -> {:cont, socket}
      true -> {:halt, ask(socket, %{event: event, params: params})}
    end
  end

  defp ask(socket, pending) do
    user = socket.assigns.current_user

    Phoenix.Component.assign(
      socket,
      :reauth,
      Map.merge(pending, %{error: nil, passkeys?: Passkeys.any?(user), challenge: nil})
    )
  end

  defp prompt_event("submit", %{"reauth" => %{"proof" => proof}}, socket, session_id) do
    %{current_user: user, reauth_meta: meta} = socket.assigns

    case TwoFactor.confirm(user, proof, meta) do
      :ok -> confirmed(socket, session_id)
      {:error, reason} -> {:halt, error(socket, reason)}
    end
  end

  defp prompt_event("cancel", _params, socket, _session_id) do
    case socket.assigns.reauth do
      %{return_to: _} -> {:halt, push_navigate(socket, to: "/admin")}
      _ -> {:halt, Phoenix.Component.assign(socket, :reauth, nil)}
    end
  end

  defp prompt_event("passkey_options", _params, socket, _session_id) do
    {challenge, options} = Passkeys.authentication_challenge(socket.assigns.current_user)
    socket = Phoenix.Component.update(socket, :reauth, &%{&1 | challenge: Brando.Redacted.wrap(challenge)})
    {:halt, %{publicKey: options}, socket}
  end

  defp prompt_event(
         "passkey",
         params,
         %{assigns: %{reauth: %{challenge: %Brando.Redacted{} = challenge}}} = socket,
         session_id
       ) do
    challenge = Brando.Redacted.value(challenge)
    %{current_user: user, reauth_meta: meta} = socket.assigns
    # A challenge answers once
    socket = Phoenix.Component.update(socket, :reauth, &%{&1 | challenge: nil})

    cond do
      Throttle.locked_until(user) ->
        {:halt, error(socket, :locked)}

      match?({:ok, _, _}, Passkeys.authenticate(user, params, challenge)) ->
        confirmed(socket, session_id)

      true ->
        case Throttle.failed(user, :confirm, meta || %{}) do
          {:locked, _} -> {:halt, error(socket, :locked)}
          :ok -> {:halt, error(socket, :passkey)}
        end
    end
  end

  defp prompt_event("passkey_error", _params, socket, _session_id), do: {:halt, error(socket, :passkey)}
  defp prompt_event(_action, _params, socket, _session_id), do: {:halt, socket}

  defp error(socket, reason), do: Phoenix.Component.update(socket, :reauth, &%{&1 | error: reason})

  # Confirmed: carry on with what was asked, or go back to the screen
  defp confirmed(socket, session_id) do
    Users.confirm_session(session_id)
    pending = socket.assigns.reauth
    socket = Phoenix.Component.assign(socket, :reauth, nil)

    case pending do
      %{return_to: return_to} ->
        {:halt, push_navigate(socket, to: return_to)}

      %{event: event, params: params} ->
        case socket.view.handle_event(event, params, socket) do
          {:noreply, socket} -> {:halt, socket}
          {:reply, _reply, socket} -> {:halt, socket}
        end
    end
  end

  ## The prompt

  @doc """
  The prompt: the password or a code from the app, or a passkey. In a dialog
  over the screen, or `inline` on the confirm page.
  """
  attr :reauth, :map, required: true
  attr :inline, :boolean, default: false

  def prompt(%{inline: true} = assigns) do
    ~H"""
    <div class="reauth-prompt reauth-prompt-page" id="reauth-prompt">
      <.prompt_form reauth={@reauth} />
      <div class="reauth-actions">
        <button type="submit" form="reauth-form" class="workspace-button primary" data-testid="reauth-submit">
          {gettext("Confirm")}
        </button>
        <.link navigate="/admin" class="workspace-button quiet">{gettext("Cancel")}</.link>
      </div>
    </div>
    """
  end

  def prompt(assigns) do
    ~H"""
    <Content.modal
      id="reauth-modal"
      title={gettext("Confirm it’s you")}
      icon="lock"
      show
      narrow
      close={JS.push("brando:reauth:cancel")}
    >
      <div class="reauth-prompt">
        <.prompt_form reauth={@reauth} />
      </div>
      <:footer>
        <button type="button" class="secondary" phx-click="brando:reauth:cancel">{gettext("Cancel")}</button>
        <button
          type="submit"
          form="reauth-form"
          class="primary"
          phx-disable-with={gettext("Checking...")}
          data-testid="reauth-submit"
        >
          {gettext("Confirm")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :reauth, :map, required: true

  defp prompt_form(assigns) do
    assigns =
      assign(assigns,
        form: Phoenix.Component.to_form(%{"proof" => ""}, as: "reauth"),
        minutes: div(window_seconds(), 60)
      )

    ~H"""
    <p class="reauth-intro">
      {gettext(
        "This needs your password, a code from your authenticator app or a passkey, since you last gave one more than %{minutes} minutes ago.",
        minutes: @minutes
      )}
    </p>
    <.form for={@form} id="reauth-form" class="reauth-form" phx-submit="brando:reauth:submit">
      <div class="field-wrapper">
        <Auth.input
          field={@form[:proof]}
          type="password"
          label={gettext("Password or code from your app")}
          autocomplete="current-password"
          data-testid="reauth-proof"
          required
          autofocus
        />
      </div>
    </.form>
    <p :if={@reauth.error} class="reauth-error" role="alert" data-testid="reauth-error">{error_message(@reauth.error)}</p>
    <div :if={@reauth.passkeys?} class="reauth-passkey">
      <span>{gettext("or")}</span>
      <button
        type="button"
        id="reauth-passkey"
        class="workspace-button"
        phx-hook="Brando.Passkey"
        data-passkey="get"
        data-options-event="brando:reauth:passkey_options"
        data-result-event="brando:reauth:passkey"
        data-error-event="brando:reauth:passkey_error"
        data-testid="reauth-passkey"
      >
        <.icon name="fingerprint-pattern" />{gettext("Use a passkey")}
      </button>
    </div>
    """
  end

  defp error_message(:invalid_proof), do: gettext("That is not your password or a current code.")
  defp error_message(:passkey), do: gettext("The passkey did not confirm it. Try again, or use your password.")

  defp error_message(:locked),
    do: gettext("Too many failed attempts. Your account is locked for a few minutes; try again later.")

  defp error_message(_), do: gettext("That did not work. Reload the page and try again.")
end
