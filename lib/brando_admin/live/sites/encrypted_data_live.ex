defmodule BrandoAdmin.Sites.EncryptedDataLive do
  @moduledoc false
  # Configuration → Encrypted data: what this installation's encryption
  # secret cannot read (`Brando.Crypto.Audit`), and the clean-up that forgets
  # it. For whoever may reset any other user's two-factor authentication: a
  # superuser, in both authorization modes. The clean-up asks for the
  # password, a code or a passkey when the session has not confirmed lately.
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  alias Brando.Authorization.Boundary
  alias Brando.Crypto.Audit
  alias Brando.Doctor.Checks.EncryptedData
  alias BrandoAdmin.Components.Workspace

  on_mount({BrandoAdmin.Reauth, events: ~w(forget_unreadable)})

  def __authorization__, do: {:access, :backend}

  @impl Phoenix.LiveView
  def mount(_params, %{"user_token" => token}, socket) do
    cond do
      not Boundary.superuser?(socket.assigns.current_user) ->
        {:ok, redirect(socket, to: "/admin/access-denied")}

      connected?(socket) ->
        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> assign(:session_id, Brando.Users.token_id(token))
         |> assign(:forgotten, nil)
         |> set_admin_locale()
         |> load()}

      true ->
        {:ok, assign(socket, :socket_connected, false)}
    end
  end

  defp load(socket), do: assign(socket, :result, EncryptedData.run(nil))

  @impl Phoenix.LiveView
  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace encrypted-data-workspace">
      <Workspace.header
        title={gettext("Encrypted data")}
        subtitle={
          gettext(
            "Two-factor secrets, webhook secrets, notification routes and Figma credentials are kept encrypted with this installation's secret."
          )
        }
      />
      <section class="workspace-panel encrypted-data-panel" data-testid="encrypted-data-state">
        <header class="workspace-panel-heading">
          <h2>{status_heading(@result.status)}</h2>
        </header>
        <div class="encrypted-data-body">
          <p>{@result.summary}</p>
          <ul :if={@result.items != []} class="encrypted-data-items" data-testid="encrypted-data-items">
            <li :for={item <- @result.items}>{item}</li>
          </ul>
          <p :if={@result.fix} class="encrypted-data-fix">{@result.fix}</p>
          <div :if={@result.status == :error} class="encrypted-data-actions">
            <button
              type="button"
              class="btn btn--danger"
              phx-click="forget_unreadable"
              data-testid="encrypted-data-forget"
              data-confirm-title={gettext("Forget what this secret cannot read?")}
              data-confirm={confirm_text(@result)}
              data-confirm-ok={gettext("Forget unreadable values")}
              data-confirm-destructive
            >
              {gettext("Forget unreadable values")}
            </button>
            <p class="encrypted-data-note">
              {gettext(
                "Users whose two-factor secret cannot be read sign in with their password and set it up again; their passkeys stay. Webhooks and routes are paused, with their secrets. Values that can be read are not touched."
              )}
            </p>
          </div>
        </div>
      </section>
      <section :if={@forgotten} class="workspace-panel encrypted-data-panel" data-testid="encrypted-data-forgotten">
        <header class="workspace-panel-heading">
          <h2>{gettext("Forgotten")}</h2>
        </header>
        <div class="encrypted-data-body">
          <p :if={EncryptedData.items(@forgotten) == []}>{gettext("Nothing needed forgetting.")}</p>
          <ul :if={EncryptedData.items(@forgotten) != []} class="encrypted-data-items">
            <li :for={item <- EncryptedData.items(@forgotten)}>{item}</li>
          </ul>
          <p :if={@forgotten.failed != []} class="encrypted-data-fix">
            {gettext("Some of it could not be forgotten (see the log). Run it again to finish.")}
          </p>
        </div>
      </section>
    </div>
    """
  end

  defp status_heading(:error), do: gettext("Values this installation cannot read")
  defp status_heading(:skipped), do: gettext("Not checked")
  defp status_heading(_status), do: gettext("Everything can be read")

  # The counts and the two causes, as the dialog's text
  defp confirm_text(result) do
    Enum.join(result.items, "\n") <> "\n\n" <> result.fix
  end

  @impl Phoenix.LiveView
  def handle_event("forget_unreadable", _params, socket) do
    case Audit.forget(socket.assigns.current_user, keep_id: socket.assigns.session_id) do
      {:ok, forgotten} ->
        send(self(), {:toast, gettext("Unreadable values forgotten")})
        {:noreply, socket |> assign(:forgotten, forgotten) |> load()}

      {:error, :forbidden} ->
        {:noreply, push_navigate(socket, to: "/admin/access-denied")}
    end
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string()
    |> Gettext.put_locale()

    socket
  end
end
