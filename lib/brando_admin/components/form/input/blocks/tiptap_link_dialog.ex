defmodule BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog do
  @moduledoc """
  LiveComponent for the TipTap link/button dialog.

  Provides URL input and identifier selection for creating links
  in TipTap rich text editors. Communicates results back to the
  TipTap hook via `push_event` through the parent Form component.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Content.SelectIdentifier

  def mount(socket) do
    {:ok,
     socket
     |> assign(:show, false)
     |> assign(:link_type, :url)
     |> assign(:url_value, "")
     |> assign(:target_blank, false)
     |> assign(:mark_type, "link")
     |> assign(:tiptap_id, nil)
     |> assign(:selected_identifier, nil)
     |> assign(:selected_identifier_id, nil)
     |> assign(:has_existing_link?, false)}
  end

  def update(%{event: :open} = assigns, socket) do
    current_href = assigns[:current_href] || ""
    current_target = assigns[:current_target]
    current_identifier_id = assigns[:current_identifier_id]
    mark_type = assigns[:mark_type] || "link"
    tiptap_id = assigns[:tiptap_id]

    {link_type, selected_identifier, selected_identifier_id} =
      if current_identifier_id do
        case Brando.Content.get_identifier(current_identifier_id) do
          {:ok, identifier} -> {:identifier, identifier, current_identifier_id}
          _ -> {:url, nil, nil}
        end
      else
        {:url, nil, nil}
      end

    url_value = if link_type == :url, do: current_href, else: ""
    target_blank = compute_target_blank(current_target, link_type, url_value)

    {:ok,
     socket
     |> assign(:show, true)
     |> assign(:link_type, link_type)
     |> assign(:url_value, url_value)
     |> assign(:target_blank, target_blank)
     |> assign(:mark_type, mark_type)
     |> assign(:tiptap_id, tiptap_id)
     |> assign(:selected_identifier, selected_identifier)
     |> assign(:selected_identifier_id, selected_identifier_id)
     |> assign(:has_existing_link?, current_href != "")
     |> assign(:language, assigns[:language])}
  end

  def update(%{event: :identifier_selected, identifier: identifier}, socket) do
    {:ok,
     socket
     |> assign(:selected_identifier, identifier)
     |> assign(:selected_identifier_id, identifier.id)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <Content.modal
        title={gettext("Link")}
        id="tiptap-link-dialog"
        auto
        show={@show}
        close={JS.push("close_dialog", target: @myself)}
      >
        <div class="form-tabs tiptap-link-tabs">
          <div class="form-tab-customs">
            <button
              type="button"
              class={@link_type == :url && "active"}
              phx-click="set_link_type"
              phx-value-type="url"
              phx-target={@myself}
            >
              {gettext("URL")}
            </button>
            <button
              type="button"
              class={@link_type == :identifier && "active"}
              phx-click="set_link_type"
              phx-value-type="identifier"
              phx-target={@myself}
            >
              {gettext("Content")}
            </button>
          </div>
        </div>

        <div :if={@link_type == :url}>
          <div class="field-wrapper">
            <div class="label-wrapper">
              <label class="control-label">
                <span>{gettext("URL")}</span>
              </label>
            </div>
            <div class="field-base">
              <input
                class="text monospace"
                type="text"
                value={@url_value}
                placeholder="https://example.com"
                phx-blur="update_url"
                phx-target={@myself}
                name="tiptap_link_url"
              />
            </div>
          </div>
        </div>

        <div :if={@link_type == :identifier}>
          <.live_component
            module={SelectIdentifier}
            id="tiptap-link-identifier-select"
            selected_identifier_id={@selected_identifier_id}
            language={@language}
            layout={:columns}
            statuses={[:published]}
            on_change={
              fn %{data: %{identifier: identifier}} ->
                send_update(__MODULE__,
                  id: @id,
                  event: :identifier_selected,
                  identifier: identifier
                )
              end
            }
          />
        </div>

        <div class="tiny-toggle-wrapper">
          <label class="switch small">
            <input
              type="checkbox"
              checked={@target_blank}
              phx-click="toggle_target_blank"
              phx-target={@myself}
            />
            <div class="slider round"></div>
          </label>
          <span class="tiny-toggle-label">{gettext("Open link in new window/tab")}</span>
        </div>

        <:footer>
          <button
            type="button"
            class="primary"
            phx-click="confirm_link"
            phx-target={@myself}
          >
            {gettext("Apply")}
          </button>
          <button
            :if={@has_existing_link?}
            type="button"
            class="tertiary ml-auto"
            phx-click="remove_link"
            phx-target={@myself}
          >
            {gettext("Remove link")}
          </button>
        </:footer>
      </Content.modal>
    </div>
    """
  end

  def handle_event("set_link_type", %{"type" => type}, socket) do
    link_type = String.to_existing_atom(type)

    target_blank =
      case link_type do
        :identifier -> false
        :url -> compute_target_blank(nil, :url, socket.assigns.url_value)
      end

    {:noreply,
     socket
     |> assign(:link_type, link_type)
     |> assign(:target_blank, target_blank)}
  end

  def handle_event("update_url", %{"value" => url}, socket) do
    target_blank = compute_target_blank(nil, :url, url)

    {:noreply,
     socket
     |> assign(:url_value, url)
     |> assign(:target_blank, target_blank)}
  end

  def handle_event("toggle_target_blank", _, socket) do
    {:noreply, assign(socket, :target_blank, !socket.assigns.target_blank)}
  end

  def handle_event("confirm_link", _, socket) do
    link_data = build_link_data(socket.assigns)
    send(self(), {:tiptap_set_link, socket.assigns.tiptap_id, link_data})
    {:noreply, assign(socket, :show, false)}
  end

  def handle_event("remove_link", _, socket) do
    link_data = %{unset: true, mark_type: socket.assigns.mark_type}
    send(self(), {:tiptap_set_link, socket.assigns.tiptap_id, link_data})
    {:noreply, assign(socket, :show, false)}
  end

  def handle_event("close_dialog", _, socket) do
    {:noreply, assign(socket, :show, false)}
  end

  # -- Private helpers

  defp compute_target_blank(current_target, _link_type, _url) when is_binary(current_target) do
    current_target == "_blank"
  end

  defp compute_target_blank(nil, :identifier, _url), do: false

  defp compute_target_blank(nil, :url, url) when is_binary(url) do
    String.starts_with?(url, "http://") or String.starts_with?(url, "https://")
  end

  defp compute_target_blank(nil, :url, _url), do: false

  defp build_link_data(%{
         link_type: :url,
         url_value: url,
         target_blank: target_blank,
         mark_type: mark_type
       }) do
    target = if target_blank, do: "_blank", else: nil
    rel = if target_blank, do: "noopener noreferrer nofollow", else: nil

    %{
      href: url,
      target: target,
      rel: rel,
      mark_type: mark_type,
      identifier_id: nil
    }
  end

  defp build_link_data(%{
         link_type: :identifier,
         selected_identifier: identifier,
         selected_identifier_id: id,
         target_blank: target_blank,
         mark_type: mark_type
       })
       when not is_nil(identifier) do
    target = if target_blank, do: "_blank", else: nil
    rel = if target_blank, do: "noopener noreferrer nofollow", else: nil

    %{
      href: identifier.url || "#",
      target: target,
      rel: rel,
      mark_type: mark_type,
      identifier_id: id
    }
  end

  defp build_link_data(%{link_type: :identifier, mark_type: mark_type}) do
    %{unset: true, mark_type: mark_type}
  end
end
