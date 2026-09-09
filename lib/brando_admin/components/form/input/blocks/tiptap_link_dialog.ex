defmodule BrandoAdmin.Components.Form.Input.Blocks.TipTapLinkDialog do
  @moduledoc "A shared, isolated draft for ordinary links, content links and button appearance."
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.RichText
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Content.SelectIdentifier

  def open(params, language) do
    fields =
      ~w(tiptap_id request_id current_href current_target current_rel current_class current_identifier_id link_text mark_type anchors appearances)a

    attrs = Map.new(fields, fn key -> {key, params[to_string(key)]} end)
    send_update(__MODULE__, Map.merge(attrs, %{id: "tiptap-link-dialog", event: :open, language: language}))
  end

  def mount(socket) do
    {:ok,
     assign(socket,
       show: false,
       link_type: :url,
       tiptap_id: nil,
       request_id: nil,
       selected_identifier: nil,
       selected_identifier_id: nil,
       has_existing_link?: false,
       anchors: [],
       language: nil,
       error: nil,
       unavailable_destination: false,
       original_class: nil,
       original_rel: nil,
       applying: false,
       appearances: ["link", "button"],
       original_target: nil,
       target_changed: false,
       draft: %{
         "url" => "",
         "text" => "",
         "anchor" => "",
         "appearance" => "link",
         "target_blank" => false,
         "nofollow" => false
       }
     )}
  end

  def update(%{event: :open} = params, socket) do
    href = params[:current_href] || ""

    identifier =
      case params[:current_identifier_id] && Brando.Content.get_identifier(params.current_identifier_id) do
        {:ok, entry} -> if RichText.allowed_uri?(entry.url), do: entry
        _ -> nil
      end

    type =
      cond do
        identifier -> :identifier
        String.starts_with?(href, "#") -> :anchor
        true -> :url
      end

    rel = String.split(params[:current_rel] || "")

    draft = %{
      "url" => href,
      "text" => params[:link_text] || "",
      "anchor" => String.trim_leading(href, "#"),
      "appearance" => params[:mark_type] || "link",
      "target_blank" => params[:current_target] == "_blank",
      "nofollow" => "nofollow" in rel
    }

    {:ok,
     assign(socket,
       show: true,
       draft: draft,
       link_type: type,
       tiptap_id: params[:tiptap_id],
       request_id: params[:request_id],
       selected_identifier: identifier,
       selected_identifier_id: identifier && identifier.id,
       unavailable_destination: !!params[:current_identifier_id] && is_nil(identifier),
       has_existing_link?: href != "",
       original_class: params[:current_class],
       original_target: params[:current_target],
       target_changed: false,
       appearances: params[:appearances] || ["link", "button"],
       original_rel: rel,
       anchors: Enum.uniq(params[:anchors] || []),
       language: params[:language],
       error: nil,
       applying: false
     )}
  end

  def update(%{event: :identifier_selected, identifier: identifier}, socket) do
    {:ok,
     assign(socket,
       selected_identifier: identifier,
       selected_identifier_id: identifier && identifier.id,
       error: nil,
       unavailable_destination: false
     )}
  end

  def update(%{event: :applied, request_id: id, applied: applied}, socket) do
    if id == socket.assigns.request_id do
      if applied do
        send(self(), {:tiptap_set_link, socket.assigns.tiptap_id, %{closed: true, request_id: id}})
        {:ok, assign(socket, applying: false, show: false)}
      else
        {:ok,
         assign(socket,
           applying: false,
           error: gettext("The text changed while this dialog was open. Cancel and select the text again.")
         )}
      end
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def render(assigns) do
    ~H"""
    <div>
      <Content.modal
        title={gettext("Edit link")}
        subtitle={if @draft["text"] == "", do: gettext("Choose a destination and link text"), else: @draft["text"]}
        icon="hero-link"
        layout="picker"
        id="tiptap-link-dialog"
        show={@show}
        close={JS.push("close_dialog", target: @myself)}
      >
        <.form
          for={%{}}
          as={:link}
          id="tiptap-link-form"
          phx-change="validate_link"
          phx-submit="confirm_link"
          phx-target={@myself}
        >
          <div class="link-picker-modes tiptap-link-tabs">
            <div class="form-tab-customs" role="group" aria-label={gettext("Link destination")}>
              <button
                type="button"
                class={@link_type == :url && "active"}
                aria-pressed={@link_type == :url}
                phx-click="set_link_type"
                phx-value-type="url"
                phx-target={@myself}
              ><.icon name="hero-globe-alt" /><span>{gettext("URL")}</span></button>
              <button
                type="button"
                class={@link_type == :identifier && "active"}
                aria-pressed={@link_type == :identifier}
                phx-click="set_link_type"
                phx-value-type="identifier"
                phx-target={@myself}
              ><.icon name="hero-document-text" /><span>{gettext("Content")}</span></button>
              <button
                type="button"
                class={@link_type == :anchor && "active"}
                aria-pressed={@link_type == :anchor}
                phx-click="set_link_type"
                phx-value-type="anchor"
                phx-target={@myself}
              ><.icon name="hero-hashtag" /><span>{gettext("Page anchor")}</span></button>
            </div>
          </div>
          <p :if={@unavailable_destination} class="tiptap-link-warning" role="status">
            {gettext("The original content destination is unavailable. Check the saved URL or choose another destination.")}
          </p>

          <div :if={@link_type != :identifier} class="tiptap-link-url-workspace">
            <div class="tiptap-link-destination">
              <div :if={@link_type == :url} class="field-wrapper">
                <label for="tiptap-link-url" class="control-label">{gettext("Destination")}</label>
                <input
                  id="tiptap-link-url"
                  class="text monospace"
                  type="text"
                  name="link[url]"
                  value={@draft["url"]}
                  placeholder="https://example.com"
                  aria-describedby="tiptap-link-url-help tiptap-link-error"
                  aria-invalid={!!@error}
                />
                <p id="tiptap-link-url-help" class="help-text">
                  {gettext("Web address, email, phone number or relative path")}
                </p>
              </div>
              <div :if={@link_type == :anchor} class="field-wrapper">
                <label for="tiptap-link-anchor" class="control-label">{gettext("Anchor on this page")}</label>
                <input
                  id="tiptap-link-anchor"
                  class="text"
                  type="text"
                  name="link[anchor]"
                  value={@draft["anchor"]}
                  list="tiptap-page-anchors"
                  placeholder="getting-here"
                  aria-describedby="tiptap-link-error"
                />
                <datalist id="tiptap-page-anchors"><option :for={anchor <- @anchors} value={anchor} /></datalist>
              </div>
            </div>
            <div class="tiptap-link-settings"><.link_fields draft={@draft} appearances={@appearances} /></div>
          </div>

          <div :if={@link_type == :identifier} class="tiptap-link-content-workspace">
            <.live_component
              module={SelectIdentifier}
              id="tiptap-link-identifier-select"
              selected_identifier_id={@selected_identifier_id}
              language={@language}
              layout={:workspace}
              initial_schema={:all}
              statuses={[:published]}
              require_url
              on_change={
                fn %{data: %{identifier: identifier}} ->
                  send_update(__MODULE__, id: @id, event: :identifier_selected, identifier: identifier)
                end
              }
            >
              <:details><.link_fields draft={@draft} appearances={@appearances} /></:details>
            </.live_component>
          </div>
          <p id="tiptap-link-error" class="tiptap-link-error" role="alert">{@error}</p>
        </.form>
        <:footer>
          <button type="button" class="secondary" phx-click="close_dialog" phx-target={@myself} disabled={@applying}>{gettext(
            "Cancel"
          )}</button>
          <button
            type="submit"
            form="tiptap-link-form"
            class="primary"
            phx-disable-with={gettext("Applying…")}
            disabled={
              @applying ||
                (@link_type == :identifier && !RichText.allowed_uri?(@selected_identifier && @selected_identifier.url))
            }
          >{gettext("Apply link")}</button>
          <button
            :if={@has_existing_link?}
            type="button"
            class="tertiary ml-auto"
            phx-click="remove_link"
            phx-target={@myself}
          >{gettext("Remove link")}</button>
        </:footer>
      </Content.modal>
    </div>
    """
  end

  attr :appearances, :list, required: true
  attr :draft, :map, required: true

  defp link_fields(assigns) do
    ~H"""
    <div class="tiptap-link-fields">
      <label class="tiptap-link-field" for="tiptap-link-text"><span>{gettext("Link text")}</span><input
        id="tiptap-link-text"
        type="text"
        class="text"
        name="link[text]"
        value={@draft["text"]}
      /></label>
      <div class="tiptap-link-field">
        <label for="tiptap-link-appearance">{gettext("Appearance")}</label><select
          id="tiptap-link-appearance"
          name="link[appearance]"
        ><option :if={"link" in @appearances} value="link" selected={@draft["appearance"] == "link"}>
          {gettext("Text link")}
        </option><option
          :if={"button" in @appearances}
          value="button"
          selected={@draft["appearance"] == "button"}
        >
          {gettext("Button")}
        </option></select>
      </div>
      <label class="tiptap-link-check"><input type="hidden" name="link[target_blank]" value="false" /><input
        type="checkbox"
        name="link[target_blank]"
        value="true"
        checked={@draft["target_blank"]}
      /><span>{gettext("Open in a new tab")}</span></label>
      <label class="tiptap-link-check"><input type="hidden" name="link[nofollow]" value="false" /><input
        type="checkbox"
        name="link[nofollow]"
        value="true"
        checked={@draft["nofollow"]}
      /><span>{gettext("Mark as nofollow")}</span></label>
    </div>
    """
  end

  def handle_event("set_link_type", %{"type" => type}, socket) when type in ["url", "identifier", "anchor"] do
    {:noreply, assign(socket, link_type: String.to_existing_atom(type), error: nil)}
  end

  def handle_event("validate_link", %{"link" => values}, socket), do: {:noreply, update_draft(socket, values)}
  def handle_event("confirm_link", _, %{assigns: %{applying: true}} = socket), do: {:noreply, socket}

  def handle_event("confirm_link", params, socket) do
    socket = update_draft(socket, Map.get(params, "link", %{}))

    case build_link_data(socket.assigns) do
      {:ok, link} ->
        send(self(), {:tiptap_set_link, socket.assigns.tiptap_id, Map.put(link, :request_id, socket.assigns.request_id)})
        {:noreply, assign(socket, :applying, true)}

      {:error, _} ->
        {:noreply, assign(socket, :error, gettext("Enter a valid destination before applying the link."))}
    end
  end

  def handle_event("remove_link", _, socket) do
    send(self(), {:tiptap_set_link, socket.assigns.tiptap_id, %{unset: true, request_id: socket.assigns.request_id}})
    {:noreply, assign(socket, :applying, true)}
  end

  def handle_event("close_dialog", _, socket), do: close(socket, %{cancel: true})

  defp close(socket, data) do
    send(self(), {:tiptap_set_link, socket.assigns.tiptap_id, Map.put(data, :request_id, socket.assigns.request_id)})
    {:noreply, assign(socket, :show, false)}
  end

  def receive_result(params) do
    send_update(__MODULE__,
      id: "tiptap-link-dialog",
      event: :applied,
      request_id: params["request_id"],
      applied: params["applied"] == true
    )
  end

  defp update_draft(socket, values) do
    draft = Map.merge(socket.assigns.draft, Map.take(values, ~w(url text anchor appearance target_blank nofollow)))

    draft =
      Enum.reduce(~w(target_blank nofollow), draft, fn key, acc -> Map.update!(acc, key, &(&1 in [true, "true"])) end)

    assign(socket,
      draft: draft,
      error: nil,
      target_changed: socket.assigns.target_changed || draft["target_blank"] != socket.assigns.draft["target_blank"]
    )
  end

  def build_link_data(assigns) do
    draft = assigns.draft

    url =
      case assigns.link_type do
        :url ->
          draft["url"]

        :anchor ->
          anchor = draft["anchor"] |> String.trim() |> String.trim_leading("#")
          if anchor != "", do: "#" <> anchor

        :identifier ->
          assigns.selected_identifier && assigns.selected_identifier.url
      end

    with {:ok, url} <- RichText.normalize_url(url), true <- draft["appearance"] in assigns.appearances do
      target =
        cond do
          draft["target_blank"] -> "_blank"
          assigns.target_changed -> nil
          true -> assigns.original_target
        end

      rel = Enum.reject(assigns.original_rel || [], &(&1 in ["nofollow", "noopener", "noreferrer"]))

      rel =
        Enum.uniq(
          rel ++ if(target, do: ["noopener", "noreferrer"], else: []) ++ if(draft["nofollow"], do: ["nofollow"], else: [])
        )

      {:ok,
       %{
         href: url,
         target: target,
         rel: if(rel == [], do: nil, else: Enum.join(rel, " ")),
         class: assigns.original_class,
         link_text: draft["text"],
         mark_type: draft["appearance"],
         identifier_id: if(assigns.link_type == :identifier, do: assigns.selected_identifier_id)
       }}
    else
      _ -> {:error, :invalid_link}
    end
  end
end
