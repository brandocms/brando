defmodule E2eProjectAdmin.ChangeTrackingLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  alias BrandoAdmin.Components.Form.Input

  def mount(_, _, socket) do
    {:ok,
     socket
     |> assign(:socket_connected, connected?(socket))
     |> assign(:form, to_form(values("original"), as: "tracking"))
     |> assign(:changes, 0)
     |> assign(:tick, 0)
     |> assign(:show?, true)
     |> assign(:submitted, nil)}
  end

  def render(assigns) do
    ~H"""
    <section id="change-tracking-fixture">
      <button id="replace-values" phx-click="replace">Replace</button>
      <button id="clear-values" phx-click="clear">Clear</button>
      <button id="unrelated-update" phx-click="tick">Unrelated update</button>
      <button id="remove-controls" phx-click="remove">Remove controls</button>
      <output id="change-count">{@changes}</output>
      <output id="tick-count">{@tick}</output>
      <output id="submitted-values">{@submitted}</output>
      <.form for={@form} id="tracking-form" phx-change="validate" phx-submit="save">
        <div :if={@show?}>
          <Input.date field={@form[:date]} label="Date" />
          <Input.datetime field={@form[:datetime]} label="Datetime" />
          <Input.code field={@form[:code]} label="Code" />
        </div>
        <button id="submit-values" type="submit">Save values</button>
      </.form>
    </section>
    """
  end

  def handle_event("replace", _, socket),
    do: {:noreply, assign(socket, :form, to_form(values("restored"), as: "tracking"))}

  def handle_event("clear", _, socket),
    do: {:noreply, assign(socket, :form, to_form(%{"date" => nil, "datetime" => nil, "code" => nil}, as: "tracking"))}

  def handle_event("tick", _, socket), do: {:noreply, update(socket, :tick, &(&1 + 1))}
  def handle_event("remove", _, socket), do: {:noreply, assign(socket, :show?, false)}

  def handle_event("validate", %{"tracking" => params}, socket) do
    {:noreply, socket |> assign(:form, to_form(params, as: "tracking")) |> update(:changes, &(&1 + 1))}
  end

  def handle_event("save", %{"tracking" => params}, socket),
    do: {:noreply, assign(socket, :submitted, Jason.encode!(params))}

  defp values("original"),
    do: %{"date" => "2026-09-01", "datetime" => "2026-09-01T12:00:00Z", "code" => "original source"}

  defp values("restored"),
    do: %{"date" => "2026-09-08", "datetime" => "2026-09-08T15:30:00Z", "code" => "restored source"}
end
