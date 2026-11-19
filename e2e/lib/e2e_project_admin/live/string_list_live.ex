defmodule E2eProjectAdmin.StringListLive do
  @moduledoc false
  # A `:string_list` with `sync_insert`, in a form that keeps its params,
  # blank rows included, and renders them back, as the Sites screen's
  # languages form does. The E2E server is single-site, so that screen is
  # not reachable there.
  use BrandoAdmin, :live_view
  alias BrandoAdmin.Components.Form.Input

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(:socket_connected, connected?(socket))
     |> assign(:form, to_form(%{"names" => ["alpha", "beta"]}, as: "list"))
     |> assign(:changes, 0)
     |> assign(:received, nil)}
  end

  def render(assigns) do
    ~H"""
    <section id="string-list-fixture">
      <output id="change-count">{@changes}</output>
      <output id="received-names">{@received}</output>
      <.form for={@form} id="string-list-form" phx-change="validate">
        <Input.string_list field={@form[:names]} label="Names" sync_insert />
      </.form>
    </section>
    """
  end

  def handle_event("validate", %{"list" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(params, as: "list"))
     |> assign(:received, Jason.encode!(params["names"]))
     |> update(:changes, &(&1 + 1))}
  end
end
