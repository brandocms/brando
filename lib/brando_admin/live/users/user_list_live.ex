defmodule BrandoAdmin.Users.UserListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Users.User
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace

  import BrandoAdmin.Utils, only: [hide_modal: 1]

  def render(assigns) do
    selected_user =
      if assigns.transfer_to_user_id do
        Enum.find(assigns.available_users, &(&1.id == assigns.transfer_to_user_id))
      end

    total = Enum.reduce(assigns.content_summary, 0, &(&1.count + &2))
    assigns = assigns |> assign(:selected_user, selected_user) |> assign(:transfer_total, total)

    ~H"""
    <div class="admin-workspace users-workspace workspace-list" data-groups={to_string(Brando.Authorization.enabled?())}>
      <Workspace.header title={gettext("Users")} subtitle={gettext("Manage accounts and access.")}>
        <.link
          :if={Brando.Authorization.Administration.can?(Brando.Authorization.Scope.current(@current_user), :read, :groups)}
          navigate="/admin/groups"
          class="workspace-button"
        >
          {gettext("Permissions")}
        </.link>
        <.link
          :if={BrandoAdmin.Authorization.allowed?(:create, @schema)}
          navigate="/admin/users/create"
          class="workspace-button primary"
        >
          {gettext("Create new")}
        </.link>
      </Workspace.header>

      <.live_component
        module={Content.List}
        id={"content_listing_#{@schema}_default"}
        schema={@schema}
        current_user={@current_user}
        uri={@uri}
        params={@params}
        listing={:default}
        empty_title={gettext("No matching users")}
        empty_description={gettext("Try another name or email address.")}
      >
        <:column_header>
          <div class="user-directory-columns" aria-hidden="true">
            <span>{gettext("User")}</span>
            <span>{if Brando.Authorization.enabled?(), do: gettext("Legacy role"), else: gettext("Role")}</span>
            <span>{gettext("Last seen")}</span>
            <span>{gettext("Last logged in")}</span>
            <span>{gettext("Status")}</span>
            <span></span>
          </div>
        </:column_header>
      </.live_component>
    </div>

    <Content.modal
      id="transfer-content-modal"
      title={gettext("Transfer content & delete user")}
      subtitle={@deleting_user && @deleting_user.name}
      icon="hero-user"
      layout="transfer"
      show={@deleting_user != nil}
      close={hide_modal("#transfer-content-modal") |> JS.push("cancel_delete")}
    >
      <div :if={@deleting_user} class="transfer-content-modal">
        <div class="transfer-main">
          <div class="transfer-source">
            <Content.modal_person user={@deleting_user} caption={user_role(@deleting_user)} />
            <span class="modal-badge">{gettext("User to delete")}</span>
          </div>
          <h3>{gettext("Transfer ownership to")}</h3>
          <p class="modal-muted">{gettext("Choose who will own %{name}’s content.", name: @deleting_user.name)}</p>
          <div class={["transfer-user-select", @user_select_open && "open"]}>
            <button
              type="button"
              class="transfer-user-trigger"
              phx-click="toggle_user_select"
              aria-expanded={to_string(@user_select_open)}
            >
              <%= if @selected_user do %>
                <Content.modal_person user={@selected_user} caption={user_role(@selected_user)} />
              <% else %>
                <span class="transfer-user-placeholder">{gettext("Select user...")}</span>
              <% end %>
              <.icon name="hero-chevron-down" />
            </button>
            <div :if={@user_select_open} class="transfer-user-options">
              <button
                :for={user <- @available_users}
                type="button"
                class="transfer-user-option"
                phx-click="select_transfer_user"
                phx-value-id={user.id}
              >
                <Content.modal_person user={user} caption={user_role(user)} />
              </button>
            </div>
          </div>
          <div class="modal-notice">
            <.icon name="hero-information-circle" /><p>
              {gettext("Content will remain in the CMS. Ownership will transfer to the selected user.")}
            </p>
          </div>
          <div class="modal-notice modal-notice--danger">
            <.icon name="hero-exclamation-triangle" /><p>
              {gettext("%{name}’s account will be deleted after the transfer.", name: @deleting_user.name)}
            </p>
          </div>
        </div>
        <div class="transfer-content-summary">
          <div class="transfer-summary-heading">
            <h3>{gettext("Content to transfer")}</h3><span class="modal-badge">{@transfer_total}</span>
          </div>
          <table :if={@content_summary != []}>
            <thead>
              <tr>
                <th>{gettext("Table")}</th><th class="right">{gettext("Entries")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @content_summary}>
                <td>{item.label}</td><td class="right">{item.count}</td>
              </tr>
            </tbody>
            <tfoot>
              <tr>
                <td>{gettext("Total")}</td><td class="right">{@transfer_total}</td>
              </tr>
            </tfoot>
          </table>
          <p :if={@content_summary == []} class="modal-muted">{gettext("This user has no content to transfer.")}</p>
        </div>
      </div>
      <:footer>
        <span class="modal-footer-note">{gettext("Content is retained.")}</span>
        <button type="button" class="secondary" phx-click={hide_modal("#transfer-content-modal") |> JS.push("cancel_delete")}>{gettext(
          "Cancel"
        )}</button>
        <button
          type="button"
          class="primary danger"
          disabled={is_nil(@transfer_to_user_id)}
          phx-click="confirm_transfer_delete"
        >{gettext("Transfer & Delete")}</button>
      </:footer>
    </Content.modal>
    """
  end

  defp user_role(%{role: :superuser}), do: gettext("Superuser")
  defp user_role(%{role: :admin}), do: gettext("Administrator")
  defp user_role(%{role: :editor}), do: gettext("Editor")
  defp user_role(%{role: role}), do: Phoenix.Naming.humanize(to_string(role))

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:deleting_user, nil)
     |> assign(:transfer_to_user_id, nil)
     |> assign(:available_users, [])
     |> assign(:content_summary, [])
     |> assign(:user_select_open, false)}
  end

  def handle_event("delete_user", %{"id" => id}, socket) do
    user = Users.get_user!(id) |> Brando.Repo.preload(:avatar)

    table_labels =
      Brando.Blueprint.list_blueprints(:include_brando)
      |> Enum.filter(&function_exported?(&1, :__schema__, 1))
      |> Map.new(&{&1.__schema__(:source), Brando.Blueprint.get_plural(&1)})

    content_summary =
      user.id
      |> Users.get_user_content_summary()
      |> Enum.map(&Map.put(&1, :label, Map.get(table_labels, &1.table, Phoenix.Naming.humanize(&1.table))))

    {:ok, all_users} =
      Users.list_users(%{
        filter: %{active: true},
        preload: [{:avatar, :join}]
      })

    available_users = Enum.reject(all_users, &(&1.id == user.id))

    {:noreply,
     socket
     |> assign(:deleting_user, user)
     |> assign(:transfer_to_user_id, nil)
     |> assign(:available_users, available_users)
     |> assign(:content_summary, content_summary)
     |> assign(:user_select_open, false)}
  end

  def handle_event("toggle_user_select", _, socket) do
    {:noreply, assign(socket, :user_select_open, !socket.assigns.user_select_open)}
  end

  def handle_event("select_transfer_user", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:transfer_to_user_id, String.to_integer(id))
     |> assign(:user_select_open, false)}
  end

  def handle_event("confirm_transfer_delete", _, socket) do
    %{deleting_user: user, transfer_to_user_id: to_id, current_user: current_user} =
      socket.assigns

    case Users.delete_user_with_transfer(user.id, to_id, current_user) do
      {:ok, _} ->
        send(self(), {:toast, gettext("User deleted and content transferred.")})
        BrandoAdmin.LiveView.Listing.update_list_entries(Users.User)

        {:noreply,
         socket
         |> assign(:deleting_user, nil)
         |> assign(:transfer_to_user_id, nil)
         |> assign(:user_select_open, false)}

      {:error, reason} ->
        send(self(), {:toast, gettext("Error deleting user: %{reason}", reason: inspect(reason))})
        {:noreply, socket}
    end
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply,
     socket
     |> assign(:deleting_user, nil)
     |> assign(:transfer_to_user_id, nil)
     |> assign(:user_select_open, false)}
  end

  def handle_event("disable_user", %{"id" => id}, socket) do
    user = Users.get_user!(id)
    Users.set_active(id, false, user)
    send(self(), {:toast, gettext("User disabled.")})
    {:noreply, socket}
  end

  def handle_event("enable_user", %{"id" => id}, socket) do
    user = Users.get_user!(id)
    Users.set_active(id, true, user)
    send(self(), {:toast, gettext("User enabled.")})
    {:noreply, socket}
  end
end
