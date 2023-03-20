defmodule BrandoAdmin.Components.GlobalTabs do
  use BrandoAdmin, :live_component
  import BrandoAdmin.Components.Form.Input.Blocks.Utils, only: [inputs_for_poly: 2]
  import Brando.Gettext
  alias Brando.Sites
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.ImagePicker

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> load_global_sets()}
  end

  def render(assigns) do
    ~H"""
    <div>
      <%= if @global_sets == [] do %>
        <.alert type={:info}>
          <%= gettext "The application currently has no globals configured" %>
        </.alert>
      <% else %>
        <div class="global-tabs">
          <.live_component module={ImagePicker} id="image-picker" />
          <div class="form-tabs">
            <div
              :for={{global_set, index} <- @indexed_global_sets}
              class="form-tab-customs">
              <button
                id={"set-#{global_set.key}-#{global_set.language}"}
                type="button"
                class={render_classes([active: @active_tab == index])}
                phx-click={JS.push("select_tab", value: %{index: index}, target: @myself)}><%= global_set.label %></button>
            </div>
          </div>
          <div
            :for={{global_set, index} <- @indexed_global_sets}
            :if={index == @active_tab}
            id={"set-#{index}"}>
            <.set_form global_set={global_set} index={index} target={@myself} />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def set_form(assigns) do
    assigns =
      assigns
      |> assign_new(:entry, fn -> assigns.global_set end)
      |> assign_new(:changeset, fn ->
        Sites.GlobalSet.changeset(assigns.global_set, %{})
      end)

    ~H"""
    <.form
      for={@changeset}
      phx-target={@target}
      phx-change="validate"
      phx-submit="submit"
      :let={f}>
      <Input.input type={:hidden} field={f[:id]} />
      <Input.input type={:hidden} field={f[:language]} />
      <Input.input type={:hidden} field={f[:label]} />
      <Input.input type={:hidden} field={f[:key]} />

      <%= for var <- inputs_for_poly(f[:globals], []) do %>
        <.live_component module={RenderVar}
          id={"set-#{@global_set.id}-#{var.id}-#{@index}"}
          var={var}
          render={:all}
          in_block />
      <% end %>

      <button class="primary"><%= gettext("Save") %></button>
    </.form>
    """
  end

  def handle_event("select_tab", %{"index" => index}, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, index)
     |> push_event("b:component:remount", %{})}
  end

  def handle_event(
        "validate",
        %{"global_set" => params},
        %{
          assigns: %{
            current_user: current_user,
            global_sets: global_sets
          }
        } = socket
      ) do
    # get entry from params id
    entry = Enum.find(global_sets, &(&1.id == String.to_integer(params["id"])))

    changeset =
      entry
      |> Sites.GlobalSet.changeset(params, current_user)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event(
        "submit",
        %{"global_set" => params},
        %{
          assigns: %{
            current_user: current_user,
            global_sets: global_sets
          }
        } = socket
      ) do
    # get entry from params id
    entry = Enum.find(global_sets, &(&1.id == String.to_integer(params["id"])))

    changeset =
      entry
      |> Sites.GlobalSet.changeset(params, current_user)
      |> Map.put(:action, :update)

    case Sites.update_global_set(changeset, current_user) do
      {:ok, _entry} ->
        send(self(), {:toast, gettext("Global set updated")})

        {:noreply,
         socket
         |> assign(:active_tab, nil)
         |> assign(changeset: changeset)
         |> load_global_sets()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp load_global_sets(socket) do
    language = socket.assigns.current_user.config.content_language

    {:ok, global_sets} =
      Sites.list_global_sets(%{filter: %{language: language}, order: "asc label"})

    indexed_global_sets = Enum.with_index(global_sets)

    socket
    |> assign(:global_sets, global_sets)
    |> assign(:indexed_global_sets, indexed_global_sets)
  end
end
