defmodule BrandoAdmin.Sites.GlobalsLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.Global
  import Ecto.Changeset
  alias Brando.Users
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Toast
  alias Brando.Globals
  alias Brando.Sites.Global
  alias Brando.Sites.GlobalCategory
  alias Surface.Components.Form

  def mount(_, %{"user_token" => token}, socket) do
    {:ok,
     socket
     |> assign_globals()
     |> assign_new_category_changeset()
     |> assign_defaults(token)
     |> assign(
       config?: false,
       category_changeset: nil,
       selected_changeset_key: nil
     )}
  end

  def render(assigns) do
    ~F"""
    <Content.Header
      title="Globals"
      subtitle="Configure global variables">
      <button type="button" class="primary" :on-click="toggle_config">
        Configure variables
      </button>
    </Content.Header>

    <div class="globals-live">
      <div class="categories shaded">
        <h2>Categories</h2>
        {#for category <- @global_categories}
          <button
            type="button"
            class={"category", selected: @selected_changeset_key == category.key}
            :on-click="select_category"
            phx-value-key={category.key}>
            {category.label}
          </button>
        {/for}
      </div>
      <div class="content">

          <Modal title="Create category" id="modal-create-category" narrow>
            <Form
              for={@new_category_changeset}
              submit={"create_category"}
              opts={onkeydown: "return event.key != 'Enter';"}
              :let={form: category_form}>
              <Input.Text form={category_form} field={:key} monospace />
              <Input.Text form={category_form} field={:label} />
              <button class="primary">Save</button>
            </Form>
          </Modal>
        {#if @config?}
          <button type="button" class="secondary" :on-click="show_modal" phx-value-id="modal-create-category">
            Create category
          </button>
        {/if}
        {#if @category_changeset}
          <button
            :if={@config?}
            type="button"
            class="secondary"
            :on-click="delete_category"
            phx-value-id={get_field(@category_changeset, :id)}>
            Delete category
          </button>
          <button
            :if={@config?}
            type="button"
            class="secondary"
            :on-click="create_global"
            phx-value-id={get_field(@category_changeset, :id)}>
            Create global
          </button>
          <Form
            for={@category_changeset}
            :let={form: category_form}>
            <h2>{get_field(@category_changeset, :label)}</h2>
            {#for global <- inputs_for(category_form, :globals)}
              <div class="global">
                {inspect global, pretty: true}
              </div>
            {/for}
          </Form>
        {#else}
          No category selected
        {/if}
      </div>
    </div>
    """
  end

  def handle_info({:save, changeset, _form}, %{assigns: %{current_user: user}} = socket) do
    list_view = Global.__modules__().admin_list_view
    singular = Global.__naming__().singular
    context = Global.__modules__().context

    case apply(context, :"update_#{singular}", [changeset, user]) do
      {:ok, _} ->
        Toast.send_delayed("#{String.capitalize(singular)} updated")
        {:noreply, push_redirect(socket, to: Brando.routes().admin_live_path(socket, list_view))}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  def handle_event(
        "create_global",
        %{"id" => id},
        %{assigns: %{category_changeset: category_changeset}} = socket
      ) do
    Globals.delete_global_category(id)

    new_global = %Global{
      key: "key",
      label: "label"
    }

    globals = get_field(category_changeset, :globals)
    updated_category_changeset = put_change(category_changeset, :globals, [new_global | globals])

    {:noreply,
     socket
     |> assign(
       category_changeset: updated_category_changeset,
       selected_changeset_key: nil
     )}
  end

  def handle_event("select_category", %{"key" => key}, socket) do
    category = Enum.find(socket.assigns.global_categories, &(&1.key == key))
    category_changeset = change(category)

    {:noreply,
     assign(socket,
       category_changeset: category_changeset,
       selected_changeset_key: key
     )}
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    Globals.delete_global_category(id)

    {:noreply,
     socket
     |> assign_globals
     |> assign(
       category_changeset: nil,
       selected_changeset_key: nil
     )}
  end

  def handle_event("create_category", %{"global_category" => params}, socket) do
    case Globals.create_global_category(params) do
      {:ok, _} ->
        Toast.send_delayed("Category created")
        Modal.hide("modal-create-category")
        {:noreply, assign_globals(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, new_category_changeset: changeset)}
    end
  end

  def handle_event("toggle_config", _, socket) do
    {:noreply, assign(socket, :config?, !socket.assigns.config?)}
  end

  def handle_event("show_modal", %{"id" => modal_id}, socket) do
    Modal.show(modal_id)
    {:noreply, socket}
  end

  def assign_globals(socket) do
    assign(socket, :global_categories, Brando.Globals.get_global_categories() |> elem(1))
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

  def assign_new_category_changeset(%{assigns: %{current_user: current_user}} = socket) do
    new_category_changeset = GlobalCategory.changeset(%GlobalCategory{}, %{}, current_user)
    assign(socket, :new_category_changeset, new_category_changeset)
  end

  def set_admin_locale(socket) do
    Gettext.put_locale(socket.assigns.current_user.language |> to_string)
    socket
  end
end
