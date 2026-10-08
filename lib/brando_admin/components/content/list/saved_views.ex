defmodule BrandoAdmin.Components.Content.List.SavedViews do
  @moduledoc """
  The listing toolbar's Views menu (`Brando.ListingViews`): pick a saved
  view, save the listing's current filters, status, sort and page size as
  one, and update, rename, share, delete or open the listing with the view
  in use.

  Applying a view patches the listing's URL to the view's parameters plus
  `view=<id>`, so the browser's back button returns to what was there before,
  and the menu knows which view is in use and whether the listing has moved
  away from it since. A view's parameters are checked against the listing as
  it is now (`Brando.ListingViews.Params.sanitize/3`): a filter, sort or
  status it no longer has is left out.

  The menu is an action menu on `Brando.FloatingDropdown`; saving and
  renaming ask for the name in a narrow `Content.modal`.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.ListingViews
  alias Brando.ListingViews.Params
  alias Brando.ListingViews.View
  alias BrandoAdmin.Components.Content

  @doc """
  The listing's URL with `view` applied: its parameters as they still apply
  to `listing` of `schema`, and its id.
  """
  def view_url(path, %View{} = view, listing, schema) do
    params = view.params |> Params.sanitize(listing, schema) |> Map.put("view", to_string(view.id))
    Content.List.listing_url(path, params)
  end

  def mount(socket) do
    {:ok, assign(socket, :dialog, nil)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(Map.take(assigns, [:id, :schema, :listing, :uri, :params, :current_user, :active_sort]))
      |> assign_new(:views, fn -> ListingViews.list_views(assigns.current_user, assigns.schema, assigns.listing.name) end)
      |> assign_new(:default_id, fn -> default_id(assigns.current_user, assigns.schema, assigns.listing.name) end)
      |> assign_new(:moderator?, fn -> ListingViews.moderator?(assigns.current_user) end)

    {:ok, assign_current(socket)}
  end

  # What the listing shows now, the view in use, and whether it moved away from it
  defp assign_current(%{assigns: assigns} = socket) do
    current =
      (assigns.uri.query || "")
      |> URI.decode_query()
      |> Params.from_query(assigns.listing, assigns.schema, assigns.active_sort)

    selected = Enum.find(assigns.views, &(to_string(&1.id) == to_string(assigns.params["view"])))

    socket
    |> assign(:current, current)
    |> assign(:selected, selected)
    |> assign(
      :modified?,
      selected != nil and current != Params.sanitize(selected.params, assigns.listing, assigns.schema)
    )
    |> assign(:can_manage?, can_manage?(selected, assigns.current_user, assigns.moderator?))
  end

  # As `ListingViews.can_manage?/2`, with the permission looked up once;
  # the context checks it again on every change.
  defp can_manage?(nil, _user, _moderator?), do: false
  defp can_manage?(%View{creator_id: id}, %{id: id}, _moderator?), do: true
  defp can_manage?(%View{shared: shared}, _user, moderator?), do: shared and moderator?

  defp default_id(user, schema, listing) do
    case ListingViews.default_view(user, schema, listing) do
      %View{id: id} -> id
      nil -> nil
    end
  end

  defp reload(%{assigns: assigns} = socket) do
    socket
    |> assign(:views, ListingViews.list_views(assigns.current_user, assigns.schema, assigns.listing.name))
    |> assign(:default_id, default_id(assigns.current_user, assigns.schema, assigns.listing.name))
    |> assign_current()
  end

  def handle_event("apply", %{"id" => id}, socket) do
    case find(socket, id) do
      nil -> {:noreply, reload(socket)}
      view -> {:noreply, push_patch(socket, to: url(socket, view))}
    end
  end

  def handle_event("open_save", _, socket) do
    form = to_form(%{"name" => "", "shared" => "false"}, as: :view)
    {:noreply, assign(socket, :dialog, %{mode: :save, view: nil, form: form})}
  end

  def handle_event("open_rename", %{"id" => id}, socket) do
    case find(socket, id) do
      nil ->
        {:noreply, reload(socket)}

      view ->
        form = to_form(%{"name" => view.name}, as: :view)
        {:noreply, assign(socket, :dialog, %{mode: :rename, view: view, form: form})}
    end
  end

  def handle_event("close_dialog", _, socket) do
    {:noreply, assign(socket, :dialog, nil)}
  end

  def handle_event("validate", %{"view" => params}, %{assigns: %{dialog: dialog}} = socket) when dialog != nil do
    {:noreply, assign(socket, :dialog, %{dialog | form: to_form(params, as: :view)})}
  end

  def handle_event("submit", %{"view" => params}, %{assigns: %{dialog: %{mode: :save}}} = socket) do
    %{current_user: user, schema: schema, listing: listing, current: current} = socket.assigns
    attrs = %{"name" => params["name"], "shared" => params["shared"] == "true", "params" => current}

    case ListingViews.create_view(user, schema, listing.name, attrs) do
      {:ok, view} ->
        toast(socket, gettext("View saved"))

        socket = socket |> assign(:dialog, nil) |> reload()
        {:noreply, push_patch(socket, to: url(socket, view), replace: true)}

      {:error, error} ->
        {:noreply, dialog_error(socket, error, params)}
    end
  end

  def handle_event("submit", %{"view" => params}, %{assigns: %{dialog: %{mode: :rename, view: view}}} = socket) do
    case ListingViews.update_view(socket.assigns.current_user, view, %{"name" => params["name"]}) do
      {:ok, _view} ->
        toast(socket, gettext("View renamed"))
        {:noreply, socket |> assign(:dialog, nil) |> reload()}

      {:error, error} ->
        {:noreply, dialog_error(socket, error, params)}
    end
  end

  def handle_event("submit", _params, socket), do: {:noreply, assign(socket, :dialog, nil)}

  def handle_event("update", %{"id" => id}, socket) do
    change(socket, id, %{"params" => socket.assigns.current}, gettext("View updated"))
  end

  def handle_event("share", %{"id" => id, "shared" => shared}, socket) do
    message = if shared == "true", do: gettext("View shared"), else: gettext("View no longer shared")
    change(socket, id, %{"shared" => shared == "true"}, message)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %View{} = view <- find(socket, id),
         {:ok, _} <- ListingViews.delete_view(socket.assigns.current_user, view) do
      toast(socket, gettext("View deleted"))
      socket = reload(socket)

      # The listing stays as it is, without the view it no longer has
      if socket.assigns.params["view"] == to_string(view.id) do
        params = socket.assigns.uri.query |> Kernel.||("") |> URI.decode_query() |> Map.delete("view")
        {:noreply, push_patch(socket, to: Content.List.listing_url(socket.assigns.uri.path, params), replace: true)}
      else
        {:noreply, socket}
      end
    else
      _ -> {:noreply, refused(socket)}
    end
  end

  def handle_event("set_default", %{"id" => id}, socket) do
    with %View{} = view <- find(socket, id),
         {:ok, _} <- ListingViews.set_default(socket.assigns.current_user, view) do
      toast(socket, gettext("The list now opens with this view"))
      {:noreply, reload(socket)}
    else
      _ -> {:noreply, refused(socket)}
    end
  end

  def handle_event("clear_default", _, socket) do
    %{current_user: user, schema: schema, listing: listing} = socket.assigns
    :ok = ListingViews.clear_default(user, schema, listing.name)
    toast(socket, gettext("The list now opens without a view"))
    {:noreply, reload(socket)}
  end

  defp change(socket, id, attrs, message) do
    with %View{} = view <- find(socket, id),
         {:ok, _view} <- ListingViews.update_view(socket.assigns.current_user, view, attrs) do
      toast(socket, message)
      {:noreply, reload(socket)}
    else
      _ -> {:noreply, refused(socket)}
    end
  end

  # Someone else may have deleted, renamed or stopped sharing it meanwhile
  defp find(socket, id) do
    case ListingViews.get_view(socket.assigns.current_user, socket.assigns.schema, socket.assigns.listing.name, id) do
      {:ok, view} -> view
      {:error, :not_found} -> nil
    end
  end

  defp refused(socket) do
    toast(socket, gettext("This view could not be changed"), :error)
    reload(socket)
  end

  defp dialog_error(socket, %Ecto.Changeset{} = changeset, params) do
    form = to_form(%{changeset | action: :validate, params: params}, as: :view)
    assign(socket, :dialog, %{socket.assigns.dialog | form: form})
  end

  defp dialog_error(socket, _error, _params), do: socket |> assign(:dialog, nil) |> refused()

  defp url(socket, view), do: view_url(socket.assigns.uri.path, view, socket.assigns.listing, socket.assigns.schema)

  defp toast(socket, message, level \\ :success) do
    BrandoAdmin.Toast.send_to(socket.assigns.current_user, message, %{level: level, type: :notification})
  end

  def render(assigns) do
    ~H"""
    <div class="saved-views">
      <div
        id={"#{@id}-menu"}
        class="saved-views-dropdown"
        phx-hook="Brando.FloatingDropdown"
        data-placement="bottom-end"
      >
        <button
          type="button"
          class="saved-views-trigger"
          data-testid="saved-views-trigger"
          popovertarget={"#{@id}-menu-items"}
          aria-haspopup="true"
          aria-expanded="false"
          aria-label={trigger_label(@selected, @modified?)}
        >
          <.icon name="bookmark" class="saved-views-icon" />
          <span class="saved-views-label">{(@selected && @selected.name) || gettext("Views")}</span>
          <span :if={@modified?} class="saved-views-changed">{gettext("changed")}</span>
          <.icon name="chevron-down" class="dropdown-chevron" />
        </button>
        <div id={"#{@id}-menu-items"} class="saved-views-menu" popover="auto" data-testid="saved-views-menu">
          <p class="saved-views-heading">{gettext("Saved views")}</p>
          <button
            :for={view <- @views}
            :key={view.id}
            type="button"
            class="saved-views-option"
            data-testid="saved-view"
            aria-current={(@selected && @selected.id == view.id && "true") || nil}
            phx-click="apply"
            phx-value-id={view.id}
            phx-target={@myself}
          >
            <.icon name="check" class="saved-views-check" />
            <span class="saved-views-name">{view.name}</span>
            <span :if={view.shared} class="badge">{gettext("Shared")}</span>
            <span :if={view.id == @default_id} class="badge">{gettext("Default")}</span>
          </button>
          <p :if={@views == []} class="saved-views-empty">{gettext("No saved views yet")}</p>
          <span class="saved-views-separator" role="separator"></span>
          <button type="button" phx-click="open_save" phx-target={@myself} aria-haspopup="dialog">
            <.icon name="plus" />
            <span>{gettext("Save current view…")}</span>
          </button>
          <%= if @selected do %>
            <button
              :if={@can_manage? and @modified?}
              type="button"
              phx-click="update"
              phx-value-id={@selected.id}
              phx-target={@myself}
            >
              <.icon name="save" />
              <span>{gettext("Update “%{name}”", name: @selected.name)}</span>
            </button>
            <button
              :if={@can_manage?}
              type="button"
              phx-click="open_rename"
              phx-value-id={@selected.id}
              phx-target={@myself}
              aria-haspopup="dialog"
            >
              <.icon name="pencil" />
              <span>{gettext("Rename “%{name}”…", name: @selected.name)}</span>
            </button>
            <button
              :if={@can_manage?}
              type="button"
              phx-click="share"
              phx-value-id={@selected.id}
              phx-value-shared={to_string(!@selected.shared)}
              phx-target={@myself}
            >
              <.icon name={if @selected.shared, do: "lock", else: "users"} />
              <span :if={!@selected.shared}>{gettext("Share with everyone who can see this list")}</span>
              <span :if={@selected.shared}>{gettext("Stop sharing")}</span>
            </button>
            <button
              :if={@selected.id != @default_id}
              type="button"
              phx-click="set_default"
              phx-value-id={@selected.id}
              phx-target={@myself}
            >
              <.icon name="star" />
              <span>{gettext("Open the list with this view")}</span>
            </button>
            <button :if={@selected.id == @default_id} type="button" phx-click="clear_default" phx-target={@myself}>
              <.icon name="star-off" />
              <span>{gettext("Open the list without a view")}</span>
            </button>
            <button
              :if={@can_manage?}
              type="button"
              class="saved-views-delete"
              phx-click="delete"
              phx-value-id={@selected.id}
              phx-target={@myself}
              data-confirm-title={gettext("Delete “%{name}”?", name: @selected.name)}
              data-confirm={delete_message(@selected)}
              data-confirm-ok={gettext("Delete view")}
              data-confirm-destructive
            >
              <.icon name="trash-2" />
              <span>{gettext("Delete “%{name}”…", name: @selected.name)}</span>
            </button>
          <% end %>
        </div>
      </div>

      <Content.modal
        :if={@dialog}
        id={"#{@id}-dialog"}
        title={dialog_title(@dialog.mode)}
        icon="bookmark"
        show
        narrow
        close={JS.push("close_dialog", target: @myself)}
        data-testid="saved-view-dialog"
      >
        <.form
          for={@dialog.form}
          id={"#{@id}-form"}
          class="saved-views-form"
          phx-change="validate"
          phx-submit="submit"
          phx-target={@myself}
        >
          <div class="saved-views-field">
            <label for={"#{@id}-name"}>{gettext("Name")}</label>
            <input
              id={"#{@id}-name"}
              type="text"
              name={@dialog.form[:name].name}
              value={@dialog.form[:name].value}
              maxlength={View.name_max()}
              autocomplete="off"
              required
              phx-mounted={JS.focus()}
              aria-describedby={@dialog.form[:name].errors != [] && "#{@id}-name-error"}
            />
            <p :for={error <- @dialog.form[:name].errors} id={"#{@id}-name-error"} class="saved-views-error">
              {name_error(error)}
            </p>
          </div>
          <label :if={@dialog.mode == :save} class="saved-views-share">
            <input type="hidden" name={@dialog.form[:shared].name} value="false" />
            <input
              type="checkbox"
              name={@dialog.form[:shared].name}
              value="true"
              checked={@dialog.form[:shared].value in [true, "true"]}
            />
            <span>{gettext("Share with everyone who can see this list")}</span>
          </label>
        </.form>
        <:footer>
          <button type="button" class="secondary" phx-click="close_dialog" phx-target={@myself}>
            {gettext("Cancel")}
          </button>
          <button type="submit" form={"#{@id}-form"} class="primary" data-testid="saved-view-submit">
            {if @dialog.mode == :save, do: gettext("Save view"), else: gettext("Rename view")}
          </button>
        </:footer>
      </Content.modal>
    </div>
    """
  end

  defp trigger_label(nil, _modified?), do: gettext("Saved views")

  defp trigger_label(view, true), do: gettext("Saved views: %{name}, changed", name: view.name)
  defp trigger_label(view, false), do: gettext("Saved views: %{name}", name: view.name)

  defp dialog_title(:save), do: gettext("Save view")
  defp dialog_title(:rename), do: gettext("Rename view")

  defp delete_message(%View{shared: true}), do: gettext("Everyone who can see this list loses this view.")
  defp delete_message(_view), do: gettext("The list stays as it is.")

  defp name_error({_message, opts}) do
    cond do
      opts[:validation] == :required -> gettext("Give the view a name")
      opts[:validation] == :length -> gettext("Use at most %{count} characters", count: opts[:count])
      opts[:constraint] == :unique -> gettext("You already have a view with this name on this list")
      true -> gettext("This name cannot be used")
    end
  end
end
