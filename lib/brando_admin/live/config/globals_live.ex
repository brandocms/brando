defmodule BrandoAdmin.Sites.GlobalsLive do
  use BrandoAdmin.LiveView.Form, schema: Brando.Sites.GlobalCategory

  import Ecto.Changeset
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias Surface.Components.Form

  alias Brando.Users
  alias Brando.Sites.GlobalCategory
  alias Brando.Content.Var
  alias Brando.Globals
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.RenderVar

  def mount(_, %{"user_token" => token}, socket) do
    {:ok,
     socket
     |> assign_defaults(token)
     |> assign_new_category_changeset()
     |> assign_globals()
     |> assign(
       config?: false,
       category_changeset: nil,
       selected_category_key: nil
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
            class={"category", selected: @selected_category_key == category.key}
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
            submit="update_category"
            :let={form: category_form}>
            <h2>{get_field(@category_changeset, :label)}</h2>
            <h3 :if={@config?}><code>{get_field(@category_changeset, :key)}</code></h3>
            {hidden_input category_form, :key}
            {hidden_input category_form, :label}
            <div class="vars">
              {#for var <- inputs_for_poly(category_form, :globals)}
                <div id={"#{category_form.id}-#{var.id}"} class={"var", shaded: @config?}>
                  <RenderVar render={:all} var={var} edit={@config?} />
                </div>
              {/for}
              <button class="primary">
                Save changes
              </button>
            </div>
          </Form>
        {#else}
          No category selected
        {/if}
      </div>
    </div>
    """
  end

  def handle_event(
        "create_category",
        %{"global_category" => params},
        %{assigns: %{current_user: user}} = socket
      ) do
    case Globals.create_global_category(Map.put(params, "globals", []), user) do
      {:ok, _} ->
        send(self(), {:toast, "Category created"})
        Modal.hide("modal-create-category")
        {:noreply, assign_globals(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, new_category_changeset: changeset)}
    end
  end

  def handle_event(
        "update_category",
        %{"global_category" => params},
        %{assigns: %{category: category, current_user: user}} = socket
      ) do
    changeset =
      category
      |> GlobalCategory.changeset(params, user)
      |> filter_deleted_globals()

    case Globals.update_global_category(changeset, user) do
      {:ok, _} ->
        send(self(), {:toast, "Category updated"})

        {:noreply,
         socket
         |> assign_globals()
         |> assign(
           selected_category_key: nil,
           category: nil,
           category_changeset: nil
         )}

      {:error, changeset} ->
        send(self(), {:toast, "Error updating category"})
        require Logger
        Logger.error(inspect(changeset, pretty: true))
        Logger.error(inspect(changeset.errors, pretty: true))
        {:noreply, assign(socket, category_changeset: changeset)}
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    Globals.delete_global_category(id)

    {:noreply,
     socket
     |> assign_globals
     |> assign(
       category_changeset: nil,
       selected_category_key: nil
     )}
  end

  def handle_event(
        "create_global",
        _,
        %{assigns: %{category_changeset: category_changeset}} = socket
      ) do
    new_global = %Var.String{
      key: "key",
      label: "label",
      type: "string",
      value: nil,
      important: false
    }

    globals = get_field(category_changeset, :globals)
    new_globals = Enum.reverse([new_global | globals])
    updated_category_changeset = put_change(category_changeset, :globals, new_globals)

    {:noreply,
     assign(
       socket,
       category_changeset: updated_category_changeset,
       selected_category_key: nil
     )}
  end

  def handle_event("select_category", %{"key" => key}, socket) do
    category = Enum.find(socket.assigns.global_categories, &(&1.key == key))
    category_changeset = change(category)

    {:noreply,
     assign(socket,
       category: category,
       category_changeset: category_changeset,
       selected_category_key: key
     )}
  end

  def handle_event("toggle_config", _, socket) do
    {:noreply, assign(socket, :config?, !socket.assigns.config?)}
  end

  def handle_event("show_modal", %{"id" => modal_id}, socket) do
    Modal.show(modal_id)
    {:noreply, socket}
  end

  def assign_globals(
        %{assigns: %{current_user: %{config: %{content_language: language}}}} = socket
      ) do
    assign(
      socket,
      :global_categories,
      Brando.Globals.list_global_categories(%{filter: %{language: language}}) |> elem(1)
    )
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

  defp filter_deleted_globals(changeset) do
    case get_field(changeset, :globals) do
      nil ->
        changeset

      data when is_list(data) ->
        filtered_globals = Enum.reject(data, & &1.marked_as_deleted)
        put_change(changeset, :globals, filtered_globals)
    end
  end
end
