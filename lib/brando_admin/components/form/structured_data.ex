defmodule BrandoAdmin.Components.Form.StructuredData do
  @moduledoc """
  The structured data inspector in an entry's Meta drawer.

  Shows the JSON-LD graph the entry's page emits (`Brando.JSONLD.Inspector`):
  one node per entity with its `@id`, edges labelled with the property that
  links them, amber or red borders on nodes Google would flag, and dashed
  nodes for what the page would gain from a field it lacks. Selecting a node
  shows where each of its properties comes from. The mapping is read-only;
  it lives in the blueprint's `json_ld_schema`.

  Loads on `load`, sent when the drawer's Structured data tab opens, so
  opening an entry costs nothing. The entry is read again on every opening,
  so the graph follows the last save.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.JSONLD.Inspector

  # prop schema, :atom, required: true
  # prop entry_id, :any
  # prop open, :any (JS that opens the drawer on this tab)

  def mount(socket) do
    {:ok, assign(socket, inspection: nil, selected: nil, error: nil, entry: nil)}
  end

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  def handle_event("load", _params, %{assigns: %{entry_id: nil}} = socket), do: {:noreply, socket}

  def handle_event("load", _params, socket) do
    %{schema: schema, entry_id: entry_id} = socket.assigns

    case Inspector.inspect_entry(schema, entry_id) do
      {:ok, inspection, entry} ->
        selected =
          if Enum.any?(inspection.nodes, &(&1.key == socket.assigns.selected)),
            do: socket.assigns.selected,
            else: inspection.main || first_key(inspection)

        {:noreply, assign(socket, inspection: inspection, entry: entry, selected: selected, error: nil)}

      {:error, _reason} ->
        {:noreply, assign(socket, inspection: nil, error: :not_found)}
    end
  end

  def handle_event("select", %{"key" => key}, socket), do: {:noreply, assign(socket, :selected, key)}

  defp first_key(%{nodes: [node | _]}), do: node.key
  defp first_key(_inspection), do: nil

  def render(assigns) do
    assigns = assign(assigns, :node, selected_node(assigns))

    ~H"""
    <div
      id={@id}
      class="structured-data"
      phx-hook="Brando.StructuredData"
      data-open={@open}
      data-copied-label={gettext("Copied")}
    >
      <%= cond do %>
        <% is_nil(@entry_id) -> %>
          <p class="structured-data-empty">
            {gettext("Save the entry to see the structured data its page gives search engines.")}
          </p>
        <% @error -> %>
          <p class="structured-data-empty">{gettext("The entry could not be read.")}</p>
        <% is_nil(@inspection) -> %>
          <p class="structured-data-empty" role="status">{gettext("Reading structured data…")}</p>
        <% is_nil(@inspection.json) -> %>
          <p class="structured-data-empty">
            {gettext("The site has no identity in this language, so its pages give no structured data.")}
          </p>
        <% true -> %>
          <div class="structured-data-inspector">
            <.graph inspection={@inspection} selected={@selected} myself={@myself} id={@id} schema={@schema} />
            <.mapping
              node={@node}
              inspection={@inspection}
              schema={@schema}
              entry={@entry}
              id={@id}
            />
          </div>
      <% end %>
    </div>
    """
  end

  defp selected_node(%{inspection: %{nodes: nodes}, selected: key}), do: Enum.find(nodes, &(&1.key == key))
  defp selected_node(_assigns), do: nil

  attr :inspection, :any, required: true
  attr :selected, :string
  attr :myself, :any
  attr :id, :string
  attr :schema, :atom

  defp graph(assigns) do
    {width, height} = Inspector.node_size()
    assigns = assign(assigns, node_width: width, node_height: height)

    ~H"""
    <div class="structured-data-graph" role="region" tabindex="0" aria-label={gettext("Structured data graph")}>
      <svg
        class="structured-data-canvas"
        width={@inspection.width}
        height={@inspection.height}
        viewBox={"0 0 #{@inspection.width} #{@inspection.height}"}
        role="group"
        aria-label={gettext("Entities on the page")}
      >
        <g class="structured-data-edges" aria-hidden="true">
          <path
            :for={edge <- @inspection.edges}
            d={edge.path}
            data-potential={to_string(potential_edge?(edge, @inspection))}
          />
          <text
            :for={edge <- @inspection.edges}
            x={edge.label_x}
            y={edge.label_y}
            text-anchor="middle"
          >
            {edge.label}
          </text>
        </g>
        <foreignObject
          :for={node <- @inspection.nodes}
          x={node.x}
          y={node.y}
          width={@node_width}
          height={@node_height}
        >
          <button
            type="button"
            class="structured-data-node"
            data-testid={"structured-data-node-#{node.type}"}
            data-potential={to_string(node.role == :potential)}
            data-level={level(node.issues)}
            aria-pressed={to_string(node.key == @selected)}
            phx-click="select"
            phx-value-key={node.key}
            phx-target={@myself}
          >
            <span class="structured-data-node-type">
              <.icon name={Inspector.icon(node.type)} />
              <span>{node.type}</span>
            </span>
            <span class="structured-data-node-id">
              <span>{subtitle(node)}</span>
              <span :if={count_label(node.issues)} class="structured-data-node-count">
                · {count_label(node.issues)}
              </span>
            </span>
          </button>
        </foreignObject>
      </svg>
    </div>
    """
  end

  attr :node, :any
  attr :inspection, :any
  attr :schema, :atom
  attr :entry, :any
  attr :id, :string

  defp mapping(assigns) do
    assigns =
      assigns
      |> assign(:fix, if(assigns.node, do: length(assigns.node.issues), else: 0))
      |> assign(:rich_results, rich_results(assigns.schema, assigns.entry, assigns.inspection))

    ~H"""
    <section class="structured-data-mapping" aria-labelledby={"#{@id}-mapping-title"}>
      <header :if={@node} class="structured-data-mapping-header">
        <h3 id={"#{@id}-mapping-title"}>{@node.type}</h3>
        <span class="badge">{origin(@node, @schema)}</span>
        <span :if={@fix > 0} class="structured-data-fix" data-level={level(@node.issues)}>
          {ngettext("%{count} to fix", "%{count} to fix", @fix)}
        </span>
      </header>

      <p :if={@node && @node.potential} class="structured-data-reason">{reason(@node)}</p>

      <ul :if={@node && @node.rows != []} class="structured-data-rows">
        <li :for={row <- @node.rows} data-status={row.status}>
          <code class="structured-data-property">{row.property}</code>
          <.icon name="arrow-left" />
          <span class="structured-data-source" data-mapped={to_string(row.source != :not_mapped)}>
            {source_label(row.source)}
          </span>
          <span class="structured-data-status" title={status_label(row.status)}>
            <.icon name={status_icon(row.status)} />
            <span class="visually-hidden">{status_label(row.status)}</span>
          </span>
          <small :for={issue <- row.issues} class="structured-data-issue" data-level={issue.level}>
            {issue_message(issue, row.property)}
          </small>
        </li>
      </ul>

      <p class="structured-data-note">
        {gettext(
          "The mapping comes from the blueprint's json_ld_schema and is read-only here. Errors are properties Google requires; warnings are properties it recommends, or values it can't read."
        )}
      </p>

      <div class="structured-data-actions">
        <button type="button" class="structured-data-action" data-copy-json-ld>
          <.icon name="copy" />
          <span data-copy-label>{gettext("Copy JSON-LD")}</span>
        </button>
        <%= case @rich_results do %>
          <% {:ok, url} -> %>
            <a class="structured-data-action" href={url} target="_blank" rel="noopener noreferrer" data-rich-results>
              <.icon name="external-link" />{gettext("Rich Results Test")}
            </a>
          <% {:disabled, reason} -> %>
            <button
              type="button"
              class="structured-data-action"
              disabled
              data-rich-results
              aria-describedby={"#{@id}-rich-results-reason"}
            >
              <.icon name="external-link" />{gettext("Rich Results Test")}
            </button>
            <span id={"#{@id}-rich-results-reason"} class="structured-data-disabled-reason">{reason}</span>
        <% end %>
        <span class="visually-hidden" role="status" aria-live="polite" data-copy-status></span>
      </div>
      <pre hidden data-json-ld>{@inspection.json}</pre>
    </section>
    """
  end

  defp potential_edge?(edge, inspection),
    do: Enum.any?(inspection.nodes, &(&1.key == edge.to and &1.role == :potential))

  defp level(issues) do
    cond do
      Enum.any?(issues, &(&1.level == :error)) -> "error"
      issues != [] -> "warning"
      true -> nil
    end
  end

  defp subtitle(%{role: :potential, property: property, potential: :not_mapped}),
    do: "#{property} · " <> gettext("not mapped")

  defp subtitle(%{role: :potential, property: property}), do: "#{property} · " <> gettext("not set")

  defp subtitle(%{role: :breadcrumb, data: data}) do
    count = data |> Map.get("itemListElement", []) |> List.wrap() |> length()
    ngettext("1 item", "%{count} items", count)
  end

  defp subtitle(%{role: :service, data: %{"services" => services}}),
    do: ngettext("1 service", "%{count} services", length(services))

  defp subtitle(%{ref: nil, role: :nested, source: {:fields, [[field | _] | _]}}), do: field
  defp subtitle(%{ref: nil, role: :nested, property: property}), do: property
  defp subtitle(%{ref: ref}), do: Inspector.short_id(ref)

  defp count_label([]), do: nil

  defp count_label(issues) do
    case Enum.count(issues, &(&1.level == :error)) do
      0 -> ngettext("1 warning", "%{count} warnings", length(issues))
      errors -> ngettext("1 error", "%{count} errors", errors)
    end
  end

  defp origin(%{role: :main}, schema), do: gettext("%{name} blueprint", name: Brando.Blueprint.get_singular(schema))
  defp origin(%{role: role}, _schema) when role in [:identity, :website, :service], do: gettext("Identity")
  defp origin(%{role: :webpage}, _schema), do: gettext("Page")
  defp origin(%{role: :breadcrumb}, _schema), do: gettext("Breadcrumbs")
  defp origin(%{role: :potential}, _schema), do: gettext("Missing")
  defp origin(%{type: "Person"}, _schema), do: gettext("Author")
  defp origin(%{type: "VideoObject"}, _schema), do: gettext("Video")
  defp origin(%{property: property}, _schema) when is_binary(property), do: property
  defp origin(_node, _schema), do: gettext("Linked")

  defp reason(%{property: "author", potential: :not_mapped}),
    do: gettext("The blueprint maps no author. A developer can add one with the :person field type.")

  defp reason(%{property: "author"}),
    do: gettext("This entry has no author. Set the field the mapping reads.")

  defp reason(%{property: "image", potential: :not_mapped}),
    do: gettext("The blueprint maps no image. A developer can add one with the :image field type.")

  defp reason(%{property: "image"}), do: gettext("This entry has no image in the field the mapping reads.")

  defp reason(%{property: "video"}),
    do:
      gettext("This entry shows no video, or its videos lack a title, a thumbnail or an upload date, which Google needs.")

  defp reason(_node), do: nil

  defp source_label({:fields, groups}), do: Enum.map_join(groups, " → ", &Enum.join(&1, ", "))
  defp source_label(:identity), do: gettext("identity")
  defp source_label(:page_url), do: gettext("page URL")
  defp source_label(:language), do: gettext("language")
  defp source_label(:seo), do: gettext("SEO settings")
  defp source_label(:breadcrumbs), do: gettext("breadcrumbs")
  defp source_label(:videos), do: gettext("video fields and blocks")
  defp source_label(:provider), do: gettext("video provider")
  defp source_label(:video_thumbnail), do: gettext("thumbnail or provider poster")
  defp source_label(:not_mapped), do: gettext("not mapped")
  defp source_label(_source), do: gettext("computed")

  defp status_icon(:ok), do: "circle-check"
  defp status_icon(:warning), do: "triangle-alert"
  defp status_icon(:error), do: "circle-x"
  defp status_icon(_status), do: "circle-dashed"

  defp status_label(:ok), do: gettext("OK")
  defp status_label(:warning), do: gettext("Warning")
  defp status_label(:error), do: gettext("Error")
  defp status_label(_status), do: gettext("Empty")

  defp issue_message(%{kind: :missing, level: level, property: property}, row_property) do
    named = String.replace(property, " | ", " " <> gettext("or") <> " ")

    cond do
      property == row_property and level == :error -> gettext("Required by Google")
      property == row_property -> gettext("Recommended by Google")
      level == :error -> gettext("Required by Google: %{property}", property: named)
      true -> gettext("Recommended by Google: %{property}", property: named)
    end
  end

  defp issue_message(%{kind: kind, property: property}, row_property) do
    message = value_message(kind)
    if property == row_property, do: message, else: "#{property}: #{message}"
  end

  @doc """
  One line for an issue, naming its property: "headline: required by
  Google", "uploadDate: not an ISO 8601 date".
  """
  @spec describe_issue(map()) :: String.t()
  def describe_issue(%{kind: :missing, level: :error, property: property}),
    do: gettext("%{property}: required by Google", property: String.replace(property, " | ", " / "))

  def describe_issue(%{kind: :missing, property: property}),
    do: gettext("%{property}: recommended by Google", property: String.replace(property, " | ", " / "))

  def describe_issue(%{kind: kind, property: property}), do: "#{property}: #{value_message(kind)}"

  defp value_message(:invalid_date), do: gettext("not an ISO 8601 date")
  defp value_message(:relative_url), do: gettext("needs an absolute URL")
  defp value_message(:empty), do: gettext("empty")
  defp value_message(:invalid_duration), do: gettext("not an ISO 8601 duration")
  defp value_message(_kind), do: gettext("not a value Google reads")

  # The page's public URL, for published entries that have one.
  defp rich_results(schema, entry, inspection) do
    cond do
      is_nil(Brando.JSONLD.Graph.path(schema, entry || %{})) ->
        {:disabled, gettext("This entry has no page of its own.")}

      not live?(entry) ->
        {:disabled, gettext("Publish the entry to test its page.")}

      true ->
        {:ok, "https://search.google.com/test/rich-results?url=" <> URI.encode_www_form(inspection.url)}
    end
  end

  defp live?(%{status: status} = entry) do
    status == :published and
      case Map.get(entry, :publish_at) do
        %DateTime{} = at -> DateTime.compare(at, DateTime.utc_now()) != :gt
        _ -> true
      end
  end

  defp live?(%{}), do: true
  defp live?(_entry), do: false
end
