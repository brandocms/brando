defmodule BrandoAdmin.Components.SystemCheck do
  @moduledoc """
  Utilities → System check: the results of `Brando.Doctor` as a settings
  list, each check's finding on the left and its status and fix on the right.

  The parent runs the checks in the background and passes `results: nil`
  until they are in, which shows a skeleton.
  """
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext

  alias Brando.Doctor

  attr :results, :list, default: nil, doc: "`Brando.Doctor.Result`s, or nil while the checks run"
  attr :failed, :boolean, default: false, doc: "the checks could not run"
  attr :socket, :any, required: true

  def card(assigns) do
    assigns =
      assign(assigns,
        busy: is_nil(assigns.results) and not assigns.failed,
        counts: assigns.results && Doctor.counts(assigns.results)
      )

    ~H"""
    <section
      id="system-check"
      class="utils-maintenance system-check"
      aria-labelledby="system-check-title"
      aria-busy={to_string(@busy)}
    >
      <div class="utils-section-heading system-check-heading">
        <div>
          <h2 id="system-check-title">{dgettext("doctor", "System check")}</h2>
          <p>
            {dgettext("doctor", "What is misconfigured or out of date. The checks only read; fixes are linked, not run.")}
          </p>
        </div>
        <div class="system-check-totals">
          <span :if={@counts} class="system-check-tally" data-testid="system-check-tally">{tally(@counts)}</span>
          <button
            type="button"
            class="utils-button"
            phx-click="refresh"
            disabled={@busy}
            aria-describedby="system-check-title"
          >
            {if @busy, do: dgettext("doctor", "Checking…"), else: dgettext("doctor", "Run again")}
          </button>
        </div>
      </div>

      <ul :if={@busy} class="system-check-list is-loading" aria-hidden="true">
        <li :for={_ <- 1..6} class="system-check-row">
          <div>
            <span class="system-check-bone is-title"></span>
            <span class="system-check-bone"></span>
          </div>
          <span class="system-check-bone is-status"></span>
        </li>
      </ul>
      <p :if={@busy} class="system-check-loading">{dgettext("doctor", "Running the checks…")}</p>

      <p :if={@failed} class="system-check-failed" role="alert">
        {dgettext("doctor", "The checks could not run. Check the application logs, or run mix brando.doctor.")}
      </p>

      <ul :if={@results} class="system-check-list">
        <li :for={result <- @results} class="system-check-row" data-check={result.id} data-status={result.status}>
          <div class="system-check-finding">
            <h3>{result.label}</h3>
            <p>{result.summary}</p>
            <small :if={result.fix && result.status != :ok}>{result.fix}</small>
            <details :if={result.items != []} class="system-check-items">
              <summary>
                {dngettext("doctor", "%{count} detail", "%{count} details", length(result.items))}
              </summary>
              <ul>
                <li :for={item <- result.items}>{item}</li>
              </ul>
            </details>
          </div>
          <div class="system-check-side">
            <span class={["system-check-status", "is-#{result.status}"]}>
              <i aria-hidden="true"></i>{status_label(result.status)}
            </span>
            <.fix_link :if={result.link && result.status in [:warning, :error]} link={result.link} socket={@socket} />
          </div>
        </li>
      </ul>
    </section>
    """
  end

  attr :link, :any, required: true
  attr :socket, :any, required: true

  defp fix_link(%{link: {"#" <> _ = anchor, label}} = assigns) do
    assigns = assign(assigns, anchor: anchor, label: label)

    ~H"""
    <a href={@anchor} class="utils-button">{@label}</a>
    """
  end

  defp fix_link(%{link: {path, label}} = assigns) when is_binary(path) do
    assigns = assign(assigns, path: path, label: label)

    ~H"""
    <.link navigate={@path} class="utils-button">{@label}</.link>
    """
  end

  defp fix_link(%{link: {view, label}} = assigns) when is_atom(view) do
    assigns = assign(assigns, path: Brando.routes().admin_live_path(assigns.socket, view), label: label)

    ~H"""
    <.link navigate={@path} class="utils-button">{@label}</.link>
    """
  end

  defp status_label(:ok), do: dgettext("doctor", "OK")
  defp status_label(:warning), do: dgettext("doctor", "Warning")
  defp status_label(:error), do: dgettext("doctor", "Error")
  defp status_label(:skipped), do: dgettext("doctor", "Skipped")

  defp tally(%{warning: 0, error: 0}), do: dgettext("doctor", "All checks passed")

  defp tally(%{warning: warnings, error: errors}) do
    [
      warnings > 0 && dngettext("doctor", "%{count} warning", "%{count} warnings", warnings),
      errors > 0 && dngettext("doctor", "%{count} error", "%{count} errors", errors)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end
end
