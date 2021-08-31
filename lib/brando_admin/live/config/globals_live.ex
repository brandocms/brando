defmodule BrandoAdmin.Sites.GlobalsLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.Global
  alias Ecto.Changeset
  alias Brando.Users
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Toast
  alias Brando.Sites.Global

  def mount(_, %{"user_token" => token}, socket) do
    {:ok,
     socket
     |> assign_globals()
     |> assign_defaults(token)}
  end

  def render(assigns) do
    ~F"""
    <Content.Header
      title="Globals"
      subtitle="Configure global variables"
      instructions="" />

    {inspect @global_categories}

    """
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_info({:save, changeset, _form}, %{assigns: %{current_user: user}} = socket) do
    list_view = Global.__modules__().admin_list_view
    singular = Global.__naming__().singular
    context = Global.__modules__().context

    case apply(context, :"update_#{singular}", [changeset, user]) do
      {:ok, _} ->
        Toast.send_delayed("#{String.capitalize(singular)} updated")
        {:noreply, push_redirect(socket, to: Brando.routes().live_path(socket, list_view))}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  def handle_event(
        "update_focal_point",
        %{"field" => field, "x" => x, "y" => y},
        %{assigns: %{changeset: changeset}} = socket
      ) do
    updated_focal = %{x: x, y: y}

    updated_field =
      changeset
      |> Changeset.get_field(String.to_existing_atom(field))
      |> Map.from_struct()
      |> Map.put(:focal, updated_focal)

    updated_changeset = Changeset.put_change(changeset, field, updated_field)
    {:noreply, assign(socket, changeset: updated_changeset)}
  end

  def assign_globals(socket) do
    assign_new(socket, :global_categories, fn ->
      Brando.Globals.get_global_categories()
    end)
  end

  def assign_defaults(socket, token) do
    socket
    |> assign_current_user(token)
    |> set_admin_locale()
  end

  def assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Users.get_user_by_session_token(token)
    end)
  end

  def set_admin_locale(socket) do
    Gettext.put_locale(socket.assigns.current_user.language |> to_string)
    socket
  end
end
