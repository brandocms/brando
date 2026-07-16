defmodule BrandoAdmin.Users.UserListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing.Compiler, schema: Brando.Users.User
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  import BrandoAdmin.Utils, only: [hide_modal: 1]

  def render(assigns) do
    selected_user =
      if assigns.transfer_to_user_id do
        Enum.find(assigns.available_users, &(&1.id == assigns.transfer_to_user_id))
      end

    assigns = assign(assigns, :selected_user, selected_user)

    ~H"""
    <Content.header title={gettext("Users")} subtitle={gettext("Overview")}>
      <.link navigate="/admin/users/create" class="primary">
        {gettext("Create new")}
      </.link>
    </Content.header>

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />

    <Content.modal
      id="transfer-content-modal"
      title={gettext("Delete user")}
      medium
      show={@deleting_user != nil}
      close={hide_modal("#transfer-content-modal") |> JS.push("cancel_delete")}
    >
      <div :if={@deleting_user} class="transfer-content-modal">
        <p class="help-text">
          {gettext(
            "When deleting a user, all content they have created must be transferred to another user. Select a user below to take over ownership of the content."
          )}
        </p>

        <h3>{gettext("Transfer content from %{name} to:", name: @deleting_user.name)}</h3>

        <div class={["transfer-user-select", @user_select_open && "open"]}>
          <%= if !@user_select_open do %>
            <button type="button" class="transfer-user-trigger" phx-click="toggle_user_select">
              <%= if @selected_user do %>
                <.user_row user={@selected_user} />
              <% else %>
                <span class="transfer-user-placeholder">{gettext("Select user...")}</span>
              <% end %>
              <.icon name="hero-chevron-down" />
            </button>
          <% else %>
            <button
              :for={user <- @available_users}
              type="button"
              class="transfer-user-option"
              phx-click="select_transfer_user"
              phx-value-id={user.id}
            >
              <.user_row user={user} />
            </button>
          <% end %>
        </div>

        <div :if={@content_summary != []} class="transfer-content-summary">
          <h3>{gettext("Content to transfer")}</h3>
          <table>
            <thead>
              <tr>
                <th>{gettext("Table")}</th>
                <th class="right">{gettext("Entries")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @content_summary}>
                <td>{item.table}</td>
                <td class="right">{item.count}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@content_summary == []} class="transfer-content-empty">
          <p>{gettext("This user has no content to transfer.")}</p>
        </div>
      </div>

      <:footer>
        <button
          type="button"
          class="primary"
          disabled={is_nil(@transfer_to_user_id)}
          phx-click="confirm_transfer_delete"
        >
          {gettext("Transfer & Delete")}
        </button>
        <button
          type="button"
          class="tertiary ml-auto"
          phx-click={hide_modal("#transfer-content-modal") |> JS.push("cancel_delete")}
        >
          {gettext("Cancel")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  defp user_row(assigns) do
    ~H"""
    <div class="transfer-user-avatar">
      <img
        :if={@user.avatar && @user.avatar.status == :processed}
        src={Brando.Utils.img_url(@user.avatar, :thumb, prefix: Brando.Utils.media_url())}
      />
      <span :if={!@user.avatar || @user.avatar.status != :processed} class="transfer-user-avatar-placeholder">
        {String.first(@user.name)}
      </span>
    </div>
    <span class="transfer-user-name">{@user.name}</span>
    """
  end

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
    user = Brando.Users.get_user!(id)
    content_summary = Brando.Users.get_user_content_summary(user.id)

    {:ok, all_users} =
      Brando.Users.list_users(%{
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

    case Brando.Users.delete_user_with_transfer(user.id, to_id, current_user) do
      {:ok, _} ->
        send(self(), {:toast, gettext("User deleted and content transferred.")})
        BrandoAdmin.LiveView.Listing.update_list_entries(Brando.Users.User)

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
    user = Brando.Users.get_user!(id)
    Brando.Users.set_active(id, false, user)
    send(self(), {:toast, gettext("User disabled.")})
    {:noreply, socket}
  end

  def handle_event("enable_user", %{"id" => id}, socket) do
    user = Brando.Users.get_user!(id)
    Brando.Users.set_active(id, true, user)
    send(self(), {:toast, gettext("User enabled.")})
    {:noreply, socket}
  end
end
