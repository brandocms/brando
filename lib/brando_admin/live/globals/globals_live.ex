defmodule BrandoAdmin.Globals.GlobalsLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.Sites.GlobalSet

  alias Brando.Sites
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form.Input.RenderVar
  import Brando.Gettext
  import BrandoAdmin.Components.Form.Input.Blocks.Utils, only: [inputs_for_poly: 3]

  def mount(_params, assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> load_global_sets()
     |> assign(:active_tab, nil)}
  end

  defp load_global_sets(socket) do
    {:ok, global_sets} = Sites.list_global_sets(%{order: "asc label"})
    assign(socket, :global_sets, global_sets)
  end

  def render(assigns) do
    ~H"""
    <Content.header
      title={gettext("Globals")}
      subtitle={gettext("Overview")} />

    <.tabs global_sets={@global_sets} active_tab={@active_tab}>
      <:tab let={%{global_set: global_set, index: index}}>
        <.set_form global_set={global_set} index={index} />
      </:tab>
    </.tabs>
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
      phx-change={JS.push("validate")}
      phx-submit={JS.push("submit")}
      let={f}>
      <%= hidden_input f, :id %>
      <%= hidden_input f, :language %>
      <%= hidden_input f, :label %>
      <%= hidden_input f, :key %>

      <%= for var <- inputs_for_poly(f, :globals, []) do %>
        <.live_component module={RenderVar}
          id={"set-#{@global_set.id}-#{var.id}-#{@index}"}
          var={var}
          render={:all} />
      <% end %>

      <button class="primary"><%= gettext("Save") %></button>
    </.form>
    """
  end

  def tabs(assigns) do
    ~H"""
    <div class="form-tabs">
      <div class="form-tab-customs">
        <%= for {global_set, index} <- Enum.with_index(@global_sets) do %>
          <button
            type="button"
            class={render_classes([active: @active_tab == index])}
            phx-click={JS.push("select_tab", value: %{index: index})}><%= global_set.label %></button>
        <% end %>
      </div>
    </div>

    <%= for {global_set, index} <- Enum.with_index(@global_sets) do %>
      <%= if index == @active_tab do %>
        <div id={"set-#{index}"}>
          <%= render_slot @tab, %{global_set: global_set, index: index} %>
        </div>
      <% end %>
    <% end %>
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
end
