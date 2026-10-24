defmodule BrandoAdmin.Components.Work do
  @moduledoc """
  Background work (`BrandoAdmin.Work`) shown on the screen that started it,
  from the `@work` assign `on_mount BrandoAdmin.Work` keeps.

      <Work.button key="shopify-policies" work={@work["shopify-policies"]} running={gettext("Fetching…")} phx-click="fetch">
        {gettext("Fetch policies")}
      </Work.button>

  The button is disabled with a spinner while the work runs, and the status
  after it says how far it has come (a count or a percentage), then how it
  ended. `status/1` is the status alone, beside a button of another kind
  (an `AIAction.button` with `busy={Work.running?(work)}`) or in a row.

  Both carry the work's `data-work-id`: while one is on the page, the admin
  shows no toast for that work. Show a key once per page: its id is the
  status's DOM id.
  """
  use BrandoAdmin, :component

  alias BrandoAdmin.Work

  attr :key, :string, required: true
  attr :work, Work, default: nil
  attr :running, :string, default: nil, doc: "the label while the work runs"
  attr :global, :boolean, default: false, doc: "work that belongs to no one site (`global: true`)"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  slot :inner_block, required: true

  def button(assigns) do
    assigns = assign(assigns, :running?, Work.running?(assigns.work))

    ~H"""
    <span class="work-action">
      <button
        type="button"
        class={["btn", @class]}
        aria-busy={@running? && "true"}
        disabled={@running? || @rest[:disabled]}
        {Map.delete(@rest, :disabled)}
      >
        <span :if={@running?} class="work-spinner" aria-hidden="true"></span>
        {if @running? && @running, do: @running, else: render_slot(@inner_block)}
      </button>
      <.status key={@key} work={@work} global={@global} />
    </span>
    """
  end

  attr :key, :string, required: true
  attr :work, Work, default: nil
  attr :global, :boolean, default: false, doc: "work that belongs to no one site (`global: true`)"
  attr :class, :any, default: nil

  def status(assigns) do
    assigns =
      assigns
      |> assign(:id, Work.id(if(assigns.global, do: nil, else: Brando.Tenant.current_prefix()), assigns.key))
      |> assign(:message, assigns.work && (assigns.work.message || Work.fallback_message(assigns.work)))

    ~H"""
    <span
      id={"work-status-" <> @id}
      class={["work-status", @class]}
      phx-hook="Brando.WorkStatus"
      data-work-id={@id}
      data-status={@work && @work.status}
      role="status"
      aria-live="polite"
    >
      <%= if @work && (@message || @work.status == :running) do %>
        <span :if={@work.status == :running} class="work-spinner" aria-hidden="true"></span>
        <span :if={@work.status != :running} class="work-dot" aria-hidden="true"></span>
        <span :if={@message} class="work-message">{@message}</span>
        <span :if={@work.status == :running && progress(@work)} class="work-count">{progress(@work)}</span>
      <% end %>
    </span>
    """
  end

  defp progress(%Work{total: total, done: done}) when is_integer(total), do: "#{done} / #{total}"
  defp progress(%Work{percent: percent}) when is_number(percent), do: "#{round(percent)}%"
  defp progress(_work), do: nil
end
