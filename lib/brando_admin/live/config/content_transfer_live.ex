defmodule BrandoAdmin.Sites.ContentTransferLive do
  @moduledoc false
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext
  alias Brando.Authorization.Boundary
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.{Catalog, Dependencies, Entries, EntryCodec, Portable}
  alias BrandoAdmin.Components.Workspace

  def __authorization__, do: {:read, :utilities}

  def mount(_, %{"user_token" => token}, socket) do
    socket = BrandoAdmin.Hooks.assign_current_user(socket, token)
    Gettext.put_locale(Brando.Gettext, to_string(socket.assigns.current_user.language))
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(
       socket_connected: connected?(socket),
       transfer_sandbox:
         if(Application.get_env(Brando.otp_app(), :sql_sandbox, false) && connected?(socket),
           do: get_connect_info(socket, :user_agent)
         ),
       tab: "export",
       language_labels: Map.new(Brando.config(:languages), &{to_string(&1[:value]), &1[:text]}),
       search: "",
       results: Catalog.search(user, "", entries: true),
       selected: %{},
       export_scope: "entries",
       include_media: true,
       include_definitions: true,
       exported: nil,
       download: nil,
       error: nil,
       busy: nil,
       archive: nil,
       filename: nil,
       plan: nil,
       targets: %{},
       dependency_mappings: %{},
       target_options: [],
       dependency_options: %{},
       result: nil,
       history: Transfer.history(user),
       restore_id: nil,
       definition_plan: nil,
       definition_references: %{},
       definition_options: %{},
       scope_label: scope_label(socket),
       destination_search: "",
       dependency_search: ""
     )
     |> allow_upload(:content_bundle,
       accept: ~w(.zip),
       max_entries: 1,
       auto_upload: true,
       max_file_size: Transfer.max_bytes()
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="admin-workspace transfer-workspace" id="content-transfer" aria-busy={to_string(@busy != nil)}>
      <span class="transfer-eyebrow">{gettext("Configuration")}</span>
      <Workspace.header
        title={gettext("Import / export")}
        subtitle={gettext("Move entries and their content between sites and environments.")}
      >
        <div class="transfer-scope">
          <Brando.HTML.Icon.icon name="hero-globe-alt" /><div>
            <span>{gettext("Current workspace")}</span><strong>{@scope_label}</strong>
          </div>
        </div>
      </Workspace.header>

      <nav class="transfer-tabs" aria-label={gettext("Content transfer workflows")}>
        <button
          type="button"
          phx-click="tab"
          phx-value-tab="export"
          aria-label={gettext("Export content")}
          aria-current={@tab == "export" && "page"}
          disabled={@busy != nil}
        >
          <Brando.HTML.Icon.icon name="hero-arrow-up-tray" />
          <span class="transfer-control-label">{gettext("Export")}</span>
        </button>
        <button
          type="button"
          phx-click="tab"
          phx-value-tab="import"
          aria-label={gettext("Import content")}
          aria-current={@tab == "import" && "page"}
          disabled={@busy != nil}
        >
          <Brando.HTML.Icon.icon name="hero-arrow-down-tray" />
          <span class="transfer-control-label">{gettext("Import")}</span>
        </button>
        <button
          type="button"
          phx-click="tab"
          phx-value-tab="history"
          aria-current={@tab == "history" && "page"}
          disabled={@busy != nil}
        >
          <Brando.HTML.Icon.icon name="hero-clock" />
          <span class="transfer-control-label">{gettext("Recent imports")}</span>
        </button>
      </nav>
      <div :if={@error} class="transfer-feedback error" role="alert">{@error}</div>
      <div :if={@busy} class="transfer-feedback" role="status" aria-live="polite">
        <span class="transfer-spinner" aria-hidden="true"></span>{@busy}
      </div>

      <section :if={@tab == "export" && !@exported} class="transfer-layout" aria-labelledby="transfer-export-heading">
        <div class="transfer-main">
          <div class="transfer-section-heading">
            <span class="transfer-step">01</span><div>
              <h2 id="transfer-export-heading">{gettext("Choose your content")}</h2><p>
                {if @export_scope == "entries",
                  do: gettext("Take complete entries with their fields, metadata and block content."),
                  else: gettext("Find an entry, then select the block fields to take with you.")}
              </p>
            </div>
          </div>
          <details class="transfer-advanced">
            <summary>{gettext("Advanced export options")}</summary>
            <form id="transfer-export-scope" phx-change="export_scope">
              <label for="export-scope">{gettext("Export scope")}</label>
              <select id="export-scope" name="scope">
                <option value="entries" selected={@export_scope == "entries"}>{gettext("Whole entries")}</option>
                <option value="fields" selected={@export_scope == "fields"}>{gettext("Block fields only")}</option>
              </select>
              <p>{gettext("Use block fields to move a layout into an entry you already have.")}</p>
            </form>
          </details>
          <form id="transfer-search" phx-change="search" phx-submit="search" class="transfer-search">
            <Brando.HTML.Icon.icon name="hero-magnifying-glass" /><label class="sr-only" for="transfer-query">{gettext(
              "Search saved content"
            )}</label>
            <input
              id="transfer-query"
              name="query"
              value={@search}
              placeholder={gettext("Search pages, fragments and content…")}
              phx-debounce="250"
              autocomplete="off"
            />
            <span>{length(@results)}</span>
          </form>
          <%!-- Keep the shortcut mounted so selection updates do not move the focused content list. --%>
          <a hidden={selected_count(@selected) == 0} href="#transfer-export-summary" class="transfer-mobile-selection">
            <span class="transfer-control-label">{selection_label(@selected, @export_scope)}</span>
            <span class="transfer-control-label">{gettext("Review selection")}</span>
          </a>
          <div class="transfer-entry-list" id="transfer-entry-list">
            <div :if={@results == []} class="transfer-empty">
              <Brando.HTML.Icon.icon name="hero-document-magnifying-glass" /><h3>{gettext("No matching content")}</h3><p>
                {gettext("Try another title or change the export scope.")}
              </p>
            </div>
            <article
              :for={entry <- @results}
              id={"transfer-entry-#{entry.key}"}
              class={["transfer-entry", Map.has_key?(@selected, entry.key) && "is-selected"]}
            >
              <div class="transfer-entry-heading">
                <div class={["transfer-entry-icon", entry.schema == "Elixir.Brando.Pages.Fragment" && "is-fragment"]}>
                  <Brando.HTML.Icon.icon name={
                    if entry.schema == "Elixir.Brando.Pages.Fragment", do: "hero-puzzle-piece", else: "hero-document-text"
                  } />
                </div>
                <div class="transfer-entry-content">
                  <h3>{entry.title}</h3>
                  <div class="transfer-meta">
                    <span>{entry.type}</span>
                    <span :if={entry.language != ""}>{Map.get(@language_labels, entry.language, String.upcase(entry.language))}</span>
                  </div>
                </div>
              </div>
              <div class="transfer-entry-footer">
                <div
                  class="transfer-field-pills"
                  role="group"
                  aria-label={gettext("Fields to export from %{title}", title: entry.title)}
                >
                  <button
                    :if={@export_scope == "entries"}
                    id={"transfer-select-#{entry.key}"}
                    type="button"
                    phx-click="toggle_entry"
                    phx-value-entry={entry.key}
                    aria-pressed={to_string(Map.has_key?(@selected, entry.key))}
                    aria-label={gettext("Select %{title}", title: entry.title)}
                  ><span class="transfer-field-check" aria-hidden="true"><Brando.HTML.Icon.icon name="hero-check" /></span><span class="transfer-control-label">{if Map.has_key?(
                                                                                                                                                                      @selected,
                                                                                                                                                                      entry.key
                                                                                                                                                                    ),
                                                                                                                                                                    do:
                                                                                                                                                                      gettext(
                                                                                                                                                                        "Entry selected"
                                                                                                                                                                      ),
                                                                                                                                                                    else:
                                                                                                                                                                      gettext(
                                                                                                                                                                        "Select entry"
                                                                                                                                                                      )}</span></button>
                  <button
                    :for={field <- if(@export_scope == "fields", do: entry.fields, else: [])}
                    id={"transfer-field-#{entry.key}-#{field.name}"}
                    type="button"
                    phx-click="toggle_field"
                    phx-value-entry={entry.key}
                    phx-value-field={field.name}
                    aria-pressed={to_string(selected?(@selected, entry.key, field.name))}
                  >
                    <span class="transfer-field-check" aria-hidden="true"><Brando.HTML.Icon.icon name="hero-check" /></span>
                    <span class="transfer-control-label">{field.label}</span>
                  </button>
                </div>
                <span :if={entry.status != ""} class="transfer-entry-status" data-status={entry.status}>
                  <span class="transfer-status-dot" aria-hidden="true"></span>
                  <span class="transfer-control-label">{status_label(entry.status)}</span>
                </span>
              </div>
            </article>
          </div>
          <p class="transfer-footnote">
            {gettext("Showing up to 60 matches. Search to narrow the list. Unsaved editor changes are not included.")}
          </p>
        </div>
        <aside class="transfer-summary" id="transfer-export-summary" tabindex="-1" aria-label={gettext("Your export")}>
          <span class="transfer-eyebrow">{gettext("Your export")}</span><h2>
            {selection_label(@selected, @export_scope)}
          </h2>
          <p :if={map_size(@selected) == 0}>
            {gettext("Choose the entries you want to move. Review related content before downloading.")}
          </p>
          <ul :if={map_size(@selected) > 0} class="transfer-selection">
            <li :for={{key, selection} <- Enum.sort(@selected)}>
              <div>
                <strong>{selection.entry.title}</strong><span>{if @export_scope == "entries",
                  do: gettext("Whole entry"),
                  else: Enum.map_join(selection.fields, ", ", &Phoenix.Naming.humanize/1)}</span>
              </div><button
                type="button"
                phx-click="remove_entry"
                phx-value-key={key}
                aria-label={gettext("Remove %{title}", title: selection.entry.title)}
              >×</button>
            </li>
          </ul>
          <form id="transfer-export-options" phx-change="export_options" class="transfer-options">
            <label><input type="checkbox" name="media" value="true" checked={@include_media} /><span><strong>{gettext(
              "Media originals"
            )}</strong><small>{gettext("Images, files and uploaded videos. Sizes are regenerated on arrival.")}</small></span></label>
            <label><input type="checkbox" name="definitions" value="true" checked={@include_definitions} /><span><strong>{gettext(
              "Required definitions"
            )}</strong><small>{gettext("Keep module lineage and include child modules and table templates.")}</small></span></label>
          </form>
          <button
            type="button"
            class="transfer-button is-primary"
            phx-click="prepare_export"
            disabled={selected_count(@selected) == 0 || @busy != nil}
          ><span class="transfer-control-label">{gettext("Prepare export")}</span></button>
          <div class="transfer-note">
            <Brando.HTML.Icon.icon name="hero-information-circle" /><p>
              {if @export_scope == "entries",
                do:
                  gettext(
                    "Entries include authored fields, metadata, owned records and all blocks. Shared references can travel with the bundle or be mapped on arrival."
                  ),
                else:
                  gettext("The complete saved field travels with you, including nested blocks and retained unused content.")}
            </p>
          </div>
        </aside>
      </section>

      <section :if={@tab == "export" && @exported} class="transfer-review" id="transfer-export-review">
        <div class="transfer-section-heading">
          <span class="transfer-step complete">✓</span><div>
            <h2>{gettext("Your bundle is ready")}</h2><p>
              {gettext("Review what is included, then download it for the destination workspace.")}
            </p>
          </div>
        </div>
        <dl class="transfer-stats">
          <div>
            <dt>{if @exported.bundle["version"] == 2, do: gettext("Entries"), else: gettext("Fields")}</dt><dd>
              {bundle_count(@exported.bundle)}
            </dd>
          </div><div>
            <dt>{gettext("Blocks")}</dt><dd>
              {Enum.sum(Enum.map(@exported.bundle["fields"], &Portable.count(&1["blocks"])))}
            </dd>
          </div><div>
            <dt>{gettext("Dependencies")}</dt><dd>{map_size(@exported.bundle["dependencies"])}</dd>
          </div><div>
            <dt>{gettext("Download size")}</dt><dd>{Brando.Utils.human_size(byte_size(@exported.binary))}</dd>
          </div>
        </dl>
        <div class="transfer-review-list">
          <article :for={entry <- @exported.bundle["entries"] || []}>
            <div>
              <h3>{entry["title"]}</h3><p>
                {gettext("Whole entry")} · {Map.get(@language_labels, entry["language"], entry["language"])}
              </p>
            </div>
            <span class="transfer-badge">{gettext("Fields, metadata & content")}</span>
          </article>
          <article :for={field <- if(@exported.bundle["version"] == 1, do: @exported.bundle["fields"], else: [])}>
            <div>
              <h3>{field["title"]}</h3><p>{Phoenix.Naming.humanize(field["field"])} · {String.upcase(field["language"])}</p>
            </div><span class="transfer-badge">{ngettext("%{count} block", "%{count} blocks", Portable.count(field["blocks"]))}</span>
          </article>
        </div>
        <section :if={@exported.bundle["version"] == 2 && related_entries(@exported.bundle) != []} class="transfer-related">
          <h3>{gettext("Related entries")}</h3>
          <p>{gettext("Include these entries too, or choose their destination when you import.")}</p>
          <div :for={dep <- related_entries(@exported.bundle)} class="transfer-related-row">
            <div><strong>{dep["label"]}</strong><span>{gettext("Referenced content")}</span></div>
            <button type="button" class="transfer-button" phx-click="include_entry" phx-value-key={dep["entry_key"]}>
              <span class="transfer-control-label">{gettext("Include entry")}</span>
            </button>
          </div>
        </section>
        <details class="transfer-details">
          <summary>{gettext("Included dependencies")}</summary><div class="transfer-dependency-list">
            <div :for={{_token, dep} <- Enum.sort(@exported.bundle["dependencies"])}>
              <span>{dep["label"]}</span><small>{Phoenix.Naming.humanize(dep["kind"])} · {if dep["original"],
                do: gettext("Original included"),
                else:
                  if(included?(@exported.bundle, dep), do: gettext("Entry included"), else: gettext("Resolve on destination"))}</small>
            </div>
          </div>
        </details>
        <div class="transfer-note">
          <Brando.HTML.Icon.icon name="hero-information-circle" /><p>
            {gettext("Application code, CSS, JavaScript and service credentials use your normal deployment.")}
          </p>
        </div>
        <div class="transfer-actions">
          <button type="button" class="transfer-button" phx-click="edit_export"><span class="transfer-control-label">{gettext(
            "Edit selection"
          )}</span></button><a
            class="transfer-button is-primary"
            id="transfer-download"
            href={@download}
            download
          ><span class="transfer-control-label">{gettext("Download content bundle")}</span></a>
        </div>
      </section>

      <section :if={@tab == "import" && !@archive && !@result} class="transfer-import-start">
        <div class="transfer-upload-card">
          <div class="transfer-section-heading">
            <span class="transfer-step blue">01</span><div>
              <h2>{gettext("Bring your content here")}</h2><p>
                {gettext("Upload a content bundle to review entries, destinations and dependencies.")}
              </p>
            </div>
          </div>
          <form id="transfer-upload-form" phx-change="validate_upload" phx-submit="read_bundle">
            <div
              class={["transfer-drop", @uploads.content_bundle.entries != [] && "has-file"]}
              phx-drop-target={@uploads.content_bundle.ref}
            >
              <div :if={@uploads.content_bundle.entries == []} class="transfer-upload-icon">
                <Brando.HTML.Icon.icon name="hero-arrow-down-tray" />
              </div>
              <label for={@uploads.content_bundle.ref} class={@uploads.content_bundle.entries != [] && "sr-only"}>
                {gettext("Choose a content bundle")}
              </label>
              <p :if={@uploads.content_bundle.entries == []}>{gettext("or drop a ZIP file here · up to 128 MB")}</p>
              <.live_file_input upload={@uploads.content_bundle} hidden={@uploads.content_bundle.entries != []} />
              <div :for={entry <- @uploads.content_bundle.entries} class="transfer-file">
                <div class="transfer-upload-icon">
                  <Brando.HTML.Icon.icon name={
                    cond do
                      upload_errors(@uploads.content_bundle, entry) != [] -> "hero-exclamation-triangle"
                      entry.done? -> "hero-document-check"
                      true -> "hero-arrow-down-tray"
                    end
                  } />
                </div>
                <strong>{cond do
                  upload_errors(@uploads.content_bundle, entry) != [] -> gettext("Upload needs attention")
                  entry.done? -> gettext("Bundle uploaded")
                  true -> gettext("Uploading bundle…")
                end}</strong>
                <p class="transfer-filename">{entry.client_name}</p>
                <span class="transfer-file-progress" role="status">
                  {Brando.Utils.human_size(entry.client_size)}
                  <span :if={upload_errors(@uploads.content_bundle, entry) == []}>
                    · {if entry.done?, do: gettext("Ready to review"), else: "#{entry.progress}%"}
                  </span>
                </span>
                <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} aria-label={gettext("Remove file")}>
                  <Brando.HTML.Icon.icon name="hero-x-mark" />
                </button>
              </div>
            </div>
            <p :for={error <- upload_errors(@uploads.content_bundle)} class="transfer-feedback error" role="alert">
              {upload_error(error)}
            </p>
            <p
              :for={entry <- @uploads.content_bundle.entries}
              :if={upload_errors(@uploads.content_bundle, entry) != []}
              class="transfer-feedback error"
              role="alert"
            >
              {Enum.map_join(upload_errors(@uploads.content_bundle, entry), " ", &upload_error/1)}
            </p>
            <div class="transfer-upload-actions">
              <p id="transfer-review-help">{gettext("Review first. Apply when you’re ready.")}</p>
              <button
                class="transfer-button is-primary is-blue"
                type="submit"
                aria-describedby="transfer-review-help"
                disabled={!upload_ready?(@uploads.content_bundle) || @busy != nil}
              >
                <Brando.HTML.Icon.icon name="hero-document-magnifying-glass" />
                <span class="transfer-control-label">{gettext("Review bundle")}</span>
              </button>
            </div>
          </form>
        </div>
        <aside class="transfer-explainer">
          <h3>{gettext("A review before every import")}</h3><ol>
            <li>
              <strong>{gettext("Choose destinations")}</strong><span>{gettext(
                "Create entries or choose existing destinations in this workspace."
              )}</span>
            </li><li>
              <strong>{gettext("Resolve dependencies")}</strong><span>{gettext(
                "Reuse matching modules, bring media, and map referenced content."
              )}</span>
            </li><li>
              <strong>{gettext("Review and apply")}</strong><span>{gettext(
                "Compare changes and apply. A recovery snapshot is saved with every import."
              )}</span>
            </li>
          </ol><p>{gettext("Uploading and previewing do not change saved content or definitions.")}</p>
        </aside>
      </section>

      <section
        :if={@tab == "import" && @archive && @plan && !@result}
        id="transfer-import-review"
        class="transfer-import-review"
      >
        <div class="transfer-package">
          <div>
            <span class="transfer-eyebrow">{gettext("Incoming bundle")}</span><h2>{@filename}</h2><p>
              {@archive.bundle["source"]["label"]} · {bundle_label(@archive.bundle)}
            </p>
          </div><button type="button" class="transfer-button" phx-click="cancel_import" disabled={@busy != nil}><span class="transfer-control-label">{gettext(
            "Cancel import"
          )}</span></button>
        </div>
        <div class="transfer-section-heading">
          <span class="transfer-step blue">02</span><div>
            <h2>
              {if @archive.bundle["version"] == 2, do: gettext("Review your entries"), else: gettext("Choose destinations")}
            </h2><p>
              {if @archive.bundle["version"] == 2,
                do: gettext("Create new entries or update existing ones. Review their keys, publication and content."),
                else: gettext("Suggestions use content keys and language. Confirm each destination before applying.")}
            </p>
          </div>
        </div>
        <form
          id="transfer-destination-search"
          hidden={@archive.bundle["version"] == 2 && !Enum.any?(@plan.entries, &(&1.mode == "update"))}
          phx-change="destination_search"
          phx-submit="destination_search"
          class="transfer-search"
        >
          <Brando.HTML.Icon.icon name="hero-magnifying-glass" /><label class="sr-only" for="destination-query">{gettext(
            "Find destination entries"
          )}</label><input
            id="destination-query"
            name="query"
            value={@destination_search}
            placeholder={gettext("Find destination entries…")}
            phx-debounce="250"
          />
        </form>
        <form :if={@archive.bundle["version"] == 1} id="transfer-mappings" phx-change="map_content">
          <div class="transfer-mapping-list">
            <article :for={field <- @plan.fields} class="transfer-mapping-row">
              <div class="transfer-source">
                <span class="transfer-eyebrow">{gettext("From bundle")}</span><h3>{field.source["title"]}</h3><p>
                  {Phoenix.Naming.humanize(field.source["field"])} · {ngettext(
                    "%{count} incoming block",
                    "%{count} incoming blocks",
                    field.incoming_count
                  )}
                </p>
              </div>
              <div class="transfer-destination">
                <label for={"target-#{field.source["key"]}"}>{gettext("Destination entry")}</label><select
                  id={"target-#{field.source["key"]}"}
                  name={"entries[#{field.source["key"]}]"}
                ><option value="">{gettext("Choose an entry…")}</option><option
                  :for={option <- entry_options(field, @target_options)}
                  value={option.key}
                  selected={selected_target(@targets, field.source["key"]) == option.key}
                >
                  {option.title} · {String.upcase(option.language)} · {option.type}
                </option></select>
                <div class="transfer-destination-controls">
                  <div>
                    <label for={"field-#{field.source["key"]}"}>{gettext("Block field")}</label><select
                      id={"field-#{field.source["key"]}"}
                      name={"fields[#{field.source["key"]}]"}
                    ><option
                      :for={option <- target_fields(field)}
                      value={option.name}
                      selected={get_in(@targets, [field.source["key"], "field"]) == option.name}
                    >
                      {option.label}
                    </option></select>
                  </div><div>
                    <label for={"mode-#{field.source["key"]}"}>{gettext("Import action")}</label><select
                      id={"mode-#{field.source["key"]}"}
                      name={"modes[#{field.source["key"]}]"}
                    ><option value="replace" selected={get_in(@targets, [field.source["key"], "mode"]) != "append"}>
                      {gettext("Replace field contents")}
                    </option><option value="append" selected={get_in(@targets, [field.source["key"], "mode"]) == "append"}>
                      {gettext("Append to existing blocks")}
                    </option></select>
                  </div>
                </div>
                <p :if={field.destination} class="transfer-field-effect">
                  {if field.mode == "append",
                    do:
                      gettext("Keep %{count} current blocks and add %{incoming}.",
                        count: field.current_count,
                        incoming: field.incoming_count
                      ),
                    else:
                      gettext("Replace %{count} current blocks with %{incoming}.",
                        count: field.current_count,
                        incoming: field.incoming_count
                      )}
                </p>
                <p :if={field.destination && field.destination.status == "published"} class="transfer-published">
                  {gettext("Published entry: the imported content becomes live after rendering.")}
                </p>
                <p :if={field.issue} class="transfer-inline-error">{field.issue}</p>
              </div>
              <details class="transfer-content-preview">
                <summary>{gettext("Compare content")}</summary><div class="transfer-compare">
                  <div>
                    <h4>{gettext("Current content")}</h4><pre>{if field.destination, do: content_text(Enum.map(field.current, &Brando.Drafts.Params.snapshot(&1.block))), else: gettext("Choose a destination to compare.")}</pre>
                  </div><div>
                    <h4>{gettext("Incoming content")}</h4><pre>{content_text(field.source["blocks"])}</pre>
                  </div>
                </div>
              </details>
            </article>
          </div>
        </form>
        <form :if={@archive.bundle["version"] == 2} id="transfer-entry-mappings" phx-change="map_entries">
          <article :for={item <- @plan.entries} id={"entry-review-#{item.source["key"]}"} class="transfer-whole-entry">
            <header class="transfer-whole-entry-header">
              <div class="transfer-source">
                <span class="transfer-eyebrow">{gettext("Whole entry")}</span><h3>{item.source["title"]}</h3>
                <p>
                  {Map.get(@language_labels, item.source["language"], item.source["language"])} · {ngettext(
                    "%{count} block",
                    "%{count} blocks",
                    item.incoming_count
                  )}
                </p>
              </div>
              <span class={["transfer-badge", item.mode == "update" && "warning"]}>{if item.mode == "create",
                do: gettext("Create new"),
                else: gettext("Update existing")}</span>
            </header>
            <div class="transfer-entry-controls">
              <div>
                <label for={"entry-action-#{item.source["key"]}"}>{gettext("Import action")}</label>
                <select id={"entry-action-#{item.source["key"]}"} name={"targets[#{item.source["key"]}][mode]"}>
                  <option value="create" selected={item.mode == "create"}>{gettext("Create a new entry")}</option>
                  <option value="update" selected={item.mode == "update"}>{gettext("Update an existing entry")}</option>
                </select>
              </div>
              <div>
                <label for={"entry-publication-#{item.source["key"]}"}>{gettext("Publication")}</label>
                <select id={"entry-publication-#{item.source["key"]}"} name={"targets[#{item.source["key"]}][publication]"}>
                  <option value="draft" selected={publication(@targets, item) == "draft"}>{gettext("Save as draft")}</option>
                  <option :if={item.mode == "update"} value="preserve" selected={publication(@targets, item) == "preserve"}>
                    {gettext("Keep destination status")}
                  </option>
                  <option value="source" selected={publication(@targets, item) == "source"}>
                    {gettext("Use source status: %{status}",
                      status: Phoenix.Naming.humanize(item.source["data"]["attributes"]["status"] || "draft")
                    )}
                  </option>
                </select>
              </div>
              <div :if={item.mode == "update"} class="transfer-entry-destination">
                <label for={"entry-target-#{item.source["key"]}"}>{gettext("Destination entry")}</label>
                <select id={"entry-target-#{item.source["key"]}"} name={"targets[#{item.source["key"]}][id]"}>
                  <option value="">{gettext("Choose an entry…")}</option>
                  <option
                    :for={
                      option <- entry_options(item, @target_options) |> Enum.filter(&(&1.schema == item.source["schema"]))
                    }
                    value={option.id}
                    selected={to_string(get_in(@targets, [item.source["key"], "id"])) == to_string(option.id)}
                  >
                    {option.title} · {Map.get(@language_labels, option.language, option.language)}
                  </option>
                </select>
              </div>
            </div>
            <div class="transfer-entry-overrides">
              <div :for={name <- Entries.editable(item.source)}>
                <label for={"entry-#{name}-#{item.source["key"]}"}>{field_label(name)}</label>
                <select
                  :if={name == "language"}
                  id={"entry-#{name}-#{item.source["key"]}"}
                  name={"targets[#{item.source["key"]}][attributes][#{name}]"}
                >
                  <option
                    :for={{code, label} <- Enum.sort(@language_labels)}
                    value={code}
                    selected={
                      (get_in(@targets, [item.source["key"], "attributes", name]) || item.source["data"]["attributes"][name]) ==
                        code
                    }
                  >
                    {label}
                  </option>
                </select>
                <input
                  :if={name != "language"}
                  id={"entry-#{name}-#{item.source["key"]}"}
                  name={"targets[#{item.source["key"]}][attributes][#{name}]"}
                  value={
                    get_in(@targets, [item.source["key"], "attributes", name]) || item.source["data"]["attributes"][name]
                  }
                  phx-debounce="350"
                />
              </div>
            </div>
            <p class="transfer-entry-effect">
              {if item.mode == "create",
                do: gettext("Create this entry with its authored fields, metadata and owned content."),
                else: gettext("Replace this entry’s authored fields, metadata and owned content with the bundle values.")}
            </p>
            <p
              :if={item.status == :published}
              class="transfer-published"
            >
              {gettext("This entry will be published. Imported content becomes live after rendering.")}
            </p>
            <p :if={item.issue} class="transfer-inline-error" role="status">{item.issue}</p>
            <details class="transfer-entry-diff">
              <summary>{gettext("Review fields & content")}</summary>
              <div
                :if={item.changes != []}
                class={["transfer-change-table", item.mode == "create" && "is-new"]}
                role="table"
                aria-label={gettext("Entry field changes")}
              >
                <div class="transfer-change-head" role="row">
                  <span role="columnheader">{gettext("Field")}</span><span :if={item.mode == "update"} role="columnheader">{gettext(
                    "Current"
                  )}</span><span role="columnheader">{gettext("After import")}</span>
                </div>
                <div :for={change <- item.changes} class="transfer-change-row" role="row">
                  <strong role="cell">{field_label(change.field)}</strong><span :if={item.mode == "update"} role="cell">{if item.mode ==
                                                                                                                              "create",
                                                                                                                            do:
                                                                                                                              "—",
                                                                                                                            else:
                                                                                                                              display_field(
                                                                                                                                change.field,
                                                                                                                                change.before,
                                                                                                                                @language_labels
                                                                                                                              )}</span><span role="cell">{display_field(
                    change.field,
                    change.after,
                    @language_labels
                  )}</span>
                </div>
              </div>
              <div class="transfer-compare">
                <div>
                  <h4>{gettext("Current block content")}</h4><pre>{if item.entry && item.mode == "update", do: content_text(Enum.flat_map(Catalog.fields(item.entry.__struct__), fn field -> Enum.map(Map.get(item.entry, field.association, []), &Brando.Drafts.Params.snapshot(&1.block)) end)), else: gettext("New entry")}</pre>
                </div>
                <div>
                  <h4>{gettext("Incoming block content")}</h4><pre>{content_text(Map.values(item.source["data"]["blocks"]) |> List.flatten())}</pre>
                </div>
              </div>
              <details class="transfer-owned-preview">
                <summary>{gettext("Metadata, assets & owned records")}</summary>
                <dl>
                  <div :for={{label, value} <- owned_details(item.source["data"], @archive.bundle["dependencies"])}>
                    <dt>{label}</dt><dd>{value}</dd>
                  </div>
                </dl>
              </details>
            </details>
          </article>
        </form>
        <section class="transfer-dependencies">
          <div class="transfer-section-heading">
            <span class="transfer-step blue">03</span><div>
              <h2>{gettext("Resolve dependencies")}</h2><p>
                {gettext("Module lineage matches automatically. Other references need a reviewed destination.")}
              </p>
            </div>
          </div>
          <p :if={@plan.dependencies == []} class="transfer-feedback">
            {gettext("This bundle has no external dependencies.")}
          </p>
          <form
            :if={Enum.any?(@plan.dependencies, &(&1.action != :create))}
            phx-change="dependency_search"
            phx-submit="dependency_search"
            class="transfer-search"
          >
            <Brando.HTML.Icon.icon name="hero-magnifying-glass" />
            <label class="sr-only" for="dependency-query">{gettext("Find destination dependencies")}</label>
            <input
              id="dependency-query"
              name="query"
              value={@dependency_search}
              placeholder={gettext("Find destination modules, media or references…")}
              phx-debounce="250"
            />
          </form>
          <form id="transfer-dependency-mappings" phx-change="map_dependencies">
            <article :for={item <- @plan.dependencies} class="transfer-dependency-row">
              <div>
                <h3>{item.dependency["label"]}</h3><span>{Phoenix.Naming.humanize(item.dependency["kind"])}</span><code :if={
                  item.dependency["uid"]
                }>{item.dependency["uid"]}</code>
              </div><div class="transfer-dependency-choice">
                <label class="sr-only" for={"dependency-#{item.token}"}>{gettext("Destination for %{label}",
                  label: item.dependency["label"]
                )}</label><select
                  id={"dependency-#{item.token}"}
                  name={"dependencies[#{item.token}]"}
                  disabled={item.dependency["kind"] == "gallery" || @busy != nil}
                ><option :if={included?(@archive.bundle, item.dependency)} value="bundle" selected={item.action == :bundle}>
                  {gettext("Use included entry")}
                </option><option value={if item.can_create?, do: "create", else: ""} selected={is_nil(item.id)}>
                  {if item.can_create?, do: gettext("Create from bundle"), else: gettext("Choose a destination…")}
                </option><option
                  :for={option <- @dependency_options[item.token] || []}
                  value={option.id}
                  selected={item.action != :bundle && item.id == option.id}
                >
                  {option.label}
                </option></select><span class={["transfer-badge", item.issue && "warning"]}>{dependency_status(item)}</span><p
                  :if={item.issue}
                  class="transfer-inline-error"
                >
                  {item.issue}
                </p>
                <p :if={item.dependency["kind"] == "gallery"} class="transfer-field-effect">
                  {gettext("A separate gallery is created for every placement. Map its images and videos below.")}
                </p>
                <p :if={Enum.any?(item.suggestions, &(&1.match == :checksum))} class="transfer-field-effect">
                  {gettext("An identical original was imported recently. Choose it above to reuse the asset.")}
                </p>
                <p :if={item.dependency["unsupported"]} class="transfer-field-effect">{item.dependency["unsupported"]}</p>
                <details :if={item.differences != []} class="transfer-content-preview">
                  <summary>{gettext("Destination definition differs")}</summary>
                  <p class="transfer-field-effect">
                    {gettext(
                      "The destination uses different %{changes}. Imported content keeps its values; new references and variables use destination defaults.",
                      changes: Enum.map_join(item.differences, ", ", &definition_change/1)
                    )}
                  </p>
                </details>
              </div>
            </article>
          </form>
          <div :if={@archive.bundle["definitions"]} class="transfer-note">
            <Brando.HTML.Icon.icon name="hero-cube" /><div>
              <p>
                {gettext("Module definitions are included. Review them if a required module is missing on this site.")}
              </p><button type="button" class="transfer-button" phx-click="preview_definitions" disabled={@busy != nil}><span class="transfer-control-label">{gettext(
                "Review included definitions"
              )}</span></button>
            </div>
          </div>
          <details
            :if={@archive.bundle["definitions"] && map_size(@archive.bundle["definitions"]["references"]) > 0}
            class="transfer-content-preview"
          >
            <summary>{gettext("Assets used by included definitions")}</summary>
            <p class="transfer-field-effect">
              {gettext(
                "Module defaults need existing destination assets before their definitions can be installed. Map them here; content media is reviewed above."
              )}
            </p>
            <form phx-change="map_definition_references">
              <div :for={{token, reference} <- @archive.bundle["definitions"]["references"]} class="transfer-dependency-row">
                <label for={"definition-ref-#{token}"}>{definition_reference_label(token, reference, @archive)}</label>
                <select id={"definition-ref-#{token}"} name={"references[#{token}]"}>
                  <option value="">{gettext("Use the content mapping if available")}</option>
                  <option
                    :for={option <- @definition_options[token] || []}
                    value={option.id}
                    selected={to_string(@definition_references[token]) == to_string(option.id)}
                  >
                    {option.label}
                  </option>
                </select>
              </div>
            </form>
          </details>
          <div :if={@definition_plan} class="transfer-definition-plan">
            <h3>{gettext("Definition changes")}</h3><p>
              {gettext(
                "Only new definitions and identical existing definitions can be installed here. Changes to existing definitions require the module migration workflow."
              )}
            </p><ul>
              <li :for={item <- @definition_plan.items}>
                {item.uid} · {item.action}<span :if={item.reason}> — {item.reason}</span>
              </li>
            </ul><button
              class="transfer-button"
              type="button"
              phx-click="install_definitions"
              disabled={!safe_definitions?(@definition_plan) || @busy != nil}
            ><span class="transfer-control-label">{gettext("Install missing definitions")}</span></button>
          </div>
        </section>
        <div class="transfer-apply-bar">
          <div>
            <strong>{if Transfer.applicable?(@plan),
              do: gettext("Ready to import"),
              else: ngettext("%{count} item needs attention", "%{count} items need attention", length(@plan.problems))}</strong><p>
              {gettext("Destination: %{scope}. A recovery snapshot is saved before content changes.", scope: @scope_label)}
            </p>
          </div><button
            type="button"
            class="transfer-button is-primary"
            id="transfer-apply"
            phx-click="apply_import"
            disabled={!Transfer.applicable?(@plan) || @busy != nil}
          ><span class="transfer-control-label">{gettext("Apply content import")}</span></button>
        </div>
      </section>

      <section :if={@tab == "import" && @result} id="transfer-result" class="transfer-result" role="status">
        <span class="transfer-result-icon"><Brando.HTML.Icon.icon name="hero-check" /></span><span class="transfer-eyebrow">{@scope_label}</span><h2>
          {gettext("Content imported")}
        </h2><p>
          {if @result.mappings["version"] == 2,
            do:
              ngettext(
                "%{count} entry saved. Your recovery snapshot is ready.",
                "%{count} entries saved. Your recovery snapshot is ready.",
                map_size(@result.after)
              ),
            else:
              ngettext(
                "%{count} field saved. Your recovery snapshot is ready.",
                "%{count} fields saved. Your recovery snapshot is ready.",
                map_size(@result.after)
              )}
        </p><div :for={refresh <- @result.refresh} class={["transfer-feedback", refresh["status"] == "failed" && "error"]}>
          {refresh_message(refresh)}
        </div><p class="transfer-footnote">
          {gettext(
            "Media processing and static-site deployment may finish separately. Use your normal publishing workflow for a static site."
          )}
        </p><div class="transfer-actions">
          <button class="transfer-button" phx-click="tab" phx-value-tab="history"><span class="transfer-control-label">{gettext(
            "View recovery snapshot"
          )}</span></button><button
            class="transfer-button is-primary"
            phx-click="new_import"
          ><span class="transfer-control-label">{gettext("Import another bundle")}</span></button>
        </div>
      </section>

      <section :if={@tab == "history"} class="transfer-history">
        <div class="transfer-section-heading">
          <span class="transfer-step">↶</span><div>
            <h2>{gettext("Recent imports")}</h2><p>
              {gettext("Your last 10 imports in this workspace. Recovery refuses to overwrite newer edits.")}
            </p>
          </div>
        </div><div :if={@history == []} class="transfer-empty">
          <Brando.HTML.Icon.icon name="hero-clock" /><h3>{gettext("No imports yet")}</h3><p>
            {gettext("Completed imports and their recovery snapshots will appear here.")}
          </p>
        </div><article :for={receipt <- @history} class="transfer-history-row">
          <div>
            <h3>
              {if receipt.mappings["version"] == 2,
                do: ngettext("%{count} entry imported", "%{count} entries imported", map_size(receipt.after)),
                else: ngettext("%{count} field imported", "%{count} fields imported", map_size(receipt.after))}
            </h3><p>
              {Calendar.strftime(receipt.inserted_at, "%d %b %Y, %H:%M UTC")}
            </p><span :if={receipt.restored_at} class="transfer-badge">{gettext("Recovered")}</span><code>{receipt.package_id}</code>
          </div><div class="transfer-actions">
            <button
              type="button"
              class="transfer-button"
              phx-click="retry_refresh"
              phx-value-id={receipt.id}
              disabled={@busy != nil}
            ><span class="transfer-control-label">{gettext("Retry rendering and media")}</span></button><button
              type="button"
              class="transfer-button"
              phx-click="review_restore"
              phx-value-id={receipt.id}
              disabled={receipt.restored_at != nil || @busy != nil}
            ><span class="transfer-control-label">{gettext("Recover previous content")}</span></button>
          </div><div :if={@restore_id == receipt.id} class="transfer-recovery-confirm">
            <p>
              {gettext(
                "Restore updated content and remove entries created by this import? Published entries are affected too. Newer edits will block recovery."
              )}
            </p><div class="transfer-actions">
              <button class="transfer-button" type="button" phx-click="cancel_restore"><span class="transfer-control-label">{gettext(
                "Cancel"
              )}</span></button><button
                class="transfer-button is-primary"
                type="button"
                phx-click="restore"
                phx-value-id={receipt.id}
                disabled={@busy != nil}
              ><span class="transfer-control-label">{gettext("Restore previous content")}</span></button>
            </div>
          </div>
        </article>
      </section>
    </div>
    """
  end

  def handle_event(_, _, %{assigns: %{busy: busy}} = socket) when not is_nil(busy), do: {:noreply, socket}

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(export import history),
    do: {:noreply, assign(socket, tab: tab, error: nil, history: Transfer.history(socket.assigns.current_user))}

  def handle_event("search", params, socket),
    do:
      {:noreply,
       assign(socket,
         search: params["query"] || "",
         results:
           Catalog.search(socket.assigns.current_user, params["query"] || "",
             entries: socket.assigns.export_scope == "entries"
           )
       )}

  def handle_event("toggle_field", %{"entry" => key, "field" => name}, socket) do
    entry = Enum.find(socket.assigns.results, &(&1.key == key))

    if socket.assigns.export_scope == "fields" && entry && Enum.any?(entry.fields, &(&1.name == name)) do
      selected = socket.assigns.selected
      fields = get_in(selected, [key, :fields]) || []
      fields = if name in fields, do: fields -- [name], else: fields ++ [name]

      selected =
        if fields == [], do: Map.delete(selected, key), else: Map.put(selected, key, %{entry: entry, fields: fields})

      {:noreply, assign(socket, selected: selected, exported: nil, error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("export_scope", %{"scope" => scope}, socket) when scope in ~w(entries fields) do
    selected =
      Map.new(socket.assigns.selected, fn {key, selection} ->
        fields = if scope == "entries", do: ["entry"], else: Enum.map(selection.entry.fields, & &1.name)
        {key, %{selection | fields: fields}}
      end)
      |> Map.reject(fn {_, selection} -> selection.fields == [] end)

    {:noreply,
     assign(socket,
       export_scope: scope,
       selected: selected,
       results: Catalog.search(socket.assigns.current_user, socket.assigns.search, entries: scope == "entries")
     )}
  end

  def handle_event("toggle_entry", %{"entry" => key}, socket) do
    entry = Enum.find(socket.assigns.results, &(&1.key == key))

    if entry && socket.assigns.export_scope == "entries" do
      selected =
        if Map.has_key?(socket.assigns.selected, key),
          do: Map.delete(socket.assigns.selected, key),
          else: Map.put(socket.assigns.selected, key, %{entry: entry, fields: ["entry"]})

      {:noreply, assign(socket, selected: selected, error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("include_entry", %{"key" => key}, socket) do
    if dep = Enum.find(related_entries(socket.assigns.exported.bundle), &(&1["entry_key"] == key)) do
      entry =
        EntryCodec.load!(dep["schema"], referenced_id(dep), socket.assigns.current_user, :export) |> Catalog.describe()

      socket = assign(socket, selected: Map.put(socket.assigns.selected, key, %{entry: entry, fields: ["entry"]}))
      handle_event("prepare_export", %{}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("map_entries", %{"targets" => targets}, socket) do
    targets =
      Map.new(targets, fn {key, target} ->
        target = Map.update(target, "attributes", %{}, &Brando.Drafts.Params.clean/1)
        previous = socket.assigns.targets[key] || %{}

        target =
          if target["mode"] != (previous["mode"] || "create"),
            do: Map.put(target, "publication", if(target["mode"] == "create", do: "draft", else: "preserve")),
            else: target

        {key, target}
      end)

    {:noreply, socket |> assign(targets: targets, error: nil) |> replan() |> assign_options()}
  end

  def handle_event("remove_entry", %{"key" => key}, socket),
    do: {:noreply, assign(socket, selected: Map.delete(socket.assigns.selected, key))}

  def handle_event("export_options", params, socket),
    do:
      {:noreply,
       assign(socket, include_media: params["media"] == "true", include_definitions: params["definitions"] == "true")}

  def handle_event("prepare_export", _, socket) do
    selectors =
      Enum.map(socket.assigns.selected, fn {_, selection} ->
        selector = %{schema: selection.entry.schema, id: selection.entry.id}
        if socket.assigns.export_scope == "fields", do: Map.put(selector, :fields, selection.fields), else: selector
      end)

    opts = [
      media: socket.assigns.include_media,
      definitions: socket.assigns.include_definitions,
      source_label: socket.assigns.scope_label
    ]

    user = socket.assigns.current_user

    run(socket, :export, gettext("Preparing your saved content and media…"), fn ->
      Transfer.export(selectors, user, opts)
    end)
  end

  def handle_event("edit_export", _, socket), do: {:noreply, assign(socket, exported: nil, download: nil)}
  def handle_event("validate_upload", _, socket), do: {:noreply, assign(socket, error: nil)}
  def handle_event("cancel_upload", %{"ref" => ref}, socket), do: {:noreply, cancel_upload(socket, :content_bundle, ref)}

  def handle_event("read_bundle", _, socket) do
    if upload_ready?(socket.assigns.uploads.content_bundle) do
      [entry] = socket.assigns.uploads.content_bundle.entries

      [result] =
        consume_uploaded_entries(socket, :content_bundle, fn %{path: path}, _ ->
          {:ok, Transfer.read(File.read!(path))}
        end)

      case result do
        {:ok, archive} ->
          {:noreply,
           socket
           |> assign(
             archive: archive,
             filename: entry.client_name,
             targets: %{},
             dependency_mappings: %{},
             result: nil,
             error: nil,
             definition_plan: nil
           )
           |> replan()
           |> assign_options()}

        {:error, message} ->
          {:noreply, assign(socket, error: message)}
      end
    else
      {:noreply, assign(socket, error: gettext("Wait for the upload to finish, then review the bundle."))}
    end
  end

  def handle_event("destination_search", params, socket),
    do:
      {:noreply,
       assign(socket,
         destination_search: params["query"] || "",
         target_options:
           Catalog.search(socket.assigns.current_user, params["query"] || "",
             action: :update,
             entries: socket.assigns.archive.bundle["version"] == 2
           )
       )}

  def handle_event("map_content", params, socket) do
    targets =
      Map.new(params["entries"] || %{}, fn {key, value} ->
        if value == "" do
          {key, nil}
        else
          [id | schema] = value |> String.split(":") |> Enum.reverse()
          schema_name = schema |> Enum.reverse() |> Enum.join(":")

          options =
            Enum.find(Catalog.schemas(), &(to_string(&1) == schema_name))
            |> then(fn schema -> if schema, do: Catalog.fields(schema), else: [] end)

          chosen = Enum.find(options, &(&1.name == get_in(params, ["fields", key]))) || List.first(options)

          {key,
           %{
             "id" => id,
             "schema" => schema_name,
             "field" => chosen && chosen.name,
             "mode" => get_in(params, ["modes", key])
           }}
        end
      end)

    {:noreply, socket |> assign(targets: targets, error: nil) |> replan()}
  end

  def handle_event("map_dependencies", params, socket),
    do:
      {:noreply,
       socket
       |> assign(
         dependency_mappings: Map.reject(params["dependencies"] || %{}, fn {_, value} -> value == "" end),
         error: nil
       )
       |> replan()}

  def handle_event("dependency_search", params, socket),
    do: {:noreply, socket |> assign(dependency_search: params["query"] || "") |> assign_options()}

  def handle_event("cancel_import", _, socket), do: {:noreply, reset_import(socket)}
  def handle_event("new_import", _, socket), do: {:noreply, reset_import(socket)}

  def handle_event("apply_import", _, socket) do
    user = socket.assigns.current_user
    plan = socket.assigns.plan

    if plan && Transfer.applicable?(plan),
      do: run(socket, :apply, gettext("Verifying and importing content…"), fn -> Transfer.apply(plan, user) end),
      else: {:noreply, socket}
  end

  def handle_event("preview_definitions", _, socket) do
    definitions = socket.assigns.archive.bundle["definitions"]

    refs =
      Map.take(socket.assigns.plan.bindings, Map.keys(definitions["references"]))
      |> Map.new(fn {key, record} -> {key, record.id} end)
      |> Map.merge(socket.assigns.definition_references)

    case Brando.Content.Definitions.plan(definitions, socket.assigns.current_user, references: refs) do
      {:ok, plan} -> {:noreply, assign(socket, definition_plan: plan, error: nil)}
      {:error, message} -> {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event("map_definition_references", params, socket) do
    references =
      (params["references"] || %{})
      |> Enum.flat_map(fn {key, value} ->
        case Integer.parse(value) do
          {id, ""} when id > 0 -> [{key, id}]
          _ -> []
        end
      end)
      |> Map.new()

    {:noreply, assign(socket, definition_references: references, definition_plan: nil, error: nil)}
  end

  def handle_event("install_definitions", _, socket) do
    plan = socket.assigns.definition_plan
    user = socket.assigns.current_user

    if plan && safe_definitions?(plan),
      do:
        run(socket, :definitions, gettext("Installing missing definitions…"), fn ->
          Brando.Content.Definitions.apply(plan, user)
        end),
      else: {:noreply, socket}
  end

  def handle_event("review_restore", %{"id" => id}, socket), do: {:noreply, assign(socket, restore_id: id)}
  def handle_event("cancel_restore", _, socket), do: {:noreply, assign(socket, restore_id: nil)}

  def handle_event("restore", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    if socket.assigns.restore_id == id,
      do: run(socket, :restore, gettext("Restoring previous content…"), fn -> Transfer.restore(id, user) end),
      else: {:noreply, socket}
  end

  def handle_event("retry_refresh", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    run(socket, :refresh, gettext("Retrying rendering…"), fn -> Transfer.retry_refresh(id, user) end)
  end

  defp run(socket, name, message, fun) do
    if socket.assigns.busy do
      {:noreply, socket}
    else
      scope = Boundary.current_scope()
      sandbox = socket.assigns.transfer_sandbox

      work =
        Brando.Tenant.capture_context(fn ->
          if sandbox, do: Phoenix.Ecto.SQL.Sandbox.allow(sandbox, Ecto.Adapters.SQL.Sandbox)
          Boundary.with_scope(scope, fun)
        end)

      {:noreply, socket |> assign(busy: message, error: nil) |> start_async(name, work)}
    end
  end

  def handle_async(:export, {:ok, {:ok, exported}}, socket) do
    token = Ecto.UUID.generate()

    Brando.Cache.put({:content_transfer_download, socket.assigns.current_user.id, token}, %{
      scope: Transfer.scope(),
      exported: exported
    })

    {:noreply, assign(socket, busy: nil, exported: exported, download: "/admin/content-transfer/download/" <> token)}
  end

  def handle_async(:apply, {:ok, {:ok, receipt}}, socket),
    do: {:noreply, assign(socket, busy: nil, result: receipt, history: Transfer.history(socket.assigns.current_user))}

  def handle_async(:definitions, {:ok, {:ok, _}}, socket),
    do: {:noreply, socket |> assign(busy: nil, definition_plan: nil) |> replan() |> assign_options()}

  def handle_async(_, {:ok, {:ok, _}}, socket),
    do: {:noreply, assign(socket, busy: nil, restore_id: nil, history: Transfer.history(socket.assigns.current_user))}

  def handle_async(_, {:ok, {:error, message}}, socket),
    do: {:noreply, assign(socket, busy: nil, error: to_string(message))}

  def handle_async(_, {:exit, _}, socket),
    do:
      {:noreply,
       assign(socket, busy: nil, error: gettext("The operation could not finish. Check recent imports before retrying."))}

  defp replan(socket) do
    case Transfer.preview(socket.assigns.archive, socket.assigns.targets, socket.assigns.current_user,
           dependencies: socket.assigns.dependency_mappings
         ) do
      {:ok, plan} -> assign(socket, plan: plan)
      {:error, message} -> socket |> reset_import() |> assign(error: message)
    end
  end

  defp assign_options(%{assigns: %{plan: nil}} = socket), do: socket

  defp assign_options(socket) do
    user = socket.assigns.current_user
    references = get_in(socket.assigns.archive.bundle, ["definitions", "references"]) || %{}

    kinds =
      Enum.map(socket.assigns.plan.dependencies, & &1.dependency["kind"])
      |> Enum.reject(&(&1 == "entry"))
      |> Kernel.++(Enum.map(references, fn {_, ref} -> ref["kind"] end))

    options_by_kind = Map.new(Enum.uniq(kinds), &{&1, Dependencies.options(&1, user, socket.assigns.dependency_search)})

    options =
      Map.new(socket.assigns.plan.dependencies, fn item ->
        selected = socket.assigns.plan.bindings[item.token]

        selected =
          if selected && selected.id > 0 && item.action != :bundle,
            do: [%{id: selected.id, label: Dependencies.label(selected)}],
            else: []

        {item.token,
         (selected ++
            item.suggestions ++
            if(item.dependency["kind"] == "gallery",
              do: [],
              else:
                if(item.dependency["kind"] == "entry",
                  do: Dependencies.options(item.dependency, user, socket.assigns.dependency_search),
                  else: options_by_kind[item.dependency["kind"]]
                )
            ))
         |> Enum.uniq_by(& &1.id)}
      end)

    definition_options =
      Map.new(references, fn {token, ref} ->
        selected =
          case socket.assigns.definition_references[token] do
            nil ->
              []

            id ->
              case Brando.Content.Transfer.Error.protect(fn -> Dependencies.load!(ref["kind"], id, user) end) do
                {:ok, record} -> [%{id: record.id, label: Dependencies.label(record)}]
                _ -> []
              end
          end

        {token, (selected ++ options_by_kind[ref["kind"]]) |> Enum.uniq_by(& &1.id)}
      end)

    assign(socket,
      definition_options: definition_options,
      dependency_options: options,
      target_options:
        Catalog.search(user, socket.assigns.destination_search,
          action: :update,
          entries: socket.assigns.archive.bundle["version"] == 2
        )
    )
  end

  defp reset_import(socket),
    do:
      assign(socket,
        archive: nil,
        plan: nil,
        result: nil,
        error: nil,
        targets: %{},
        dependency_mappings: %{},
        definition_plan: nil,
        definition_references: %{},
        definition_options: %{}
      )

  defp referenced_id(dep), do: dep["entry_key"] |> String.split(":") |> List.last() |> Catalog.id!()

  defp owned_details(node, dependencies, prefix \\ nil) do
    attributes =
      if prefix,
        do:
          Enum.map(node["attributes"], fn {name, value} ->
            {prefix <> " · " <> Phoenix.Naming.humanize(name), display_value(value)}
          end),
        else: []

    references =
      Enum.flat_map(node["references"], fn {name, tokens} ->
        Enum.map(List.wrap(tokens), fn token ->
          {Enum.join(Enum.reject([prefix, Phoenix.Naming.humanize(name)], &is_nil/1), " · "),
           dependencies[token]["label"]}
        end)
      end)

    children =
      Enum.flat_map(node["owned"], fn {name, values} ->
        Enum.with_index(List.wrap(values), 1)
        |> Enum.flat_map(fn {child, index} ->
          owned_details(
            child,
            dependencies,
            Enum.join(Enum.reject([prefix, Phoenix.Naming.humanize(name) <> " " <> to_string(index)], &is_nil/1), " · ")
          )
        end)
      end)

    (attributes ++ references ++ children) |> Enum.reject(fn {_, value} -> value in ["—", "false", "[]", "{}"] end)
  end

  defp bundle_count(bundle), do: length(bundle["entries"] || bundle["fields"])
  defp bundle_label(%{"version" => 2} = bundle), do: ngettext("%{count} entry", "%{count} entries", bundle_count(bundle))
  defp bundle_label(bundle), do: ngettext("%{count} field", "%{count} fields", bundle_count(bundle))

  defp selection_label(selected, "entries"),
    do: ngettext("%{count} entry selected", "%{count} entries selected", map_size(selected))

  defp selection_label(selected, _),
    do: ngettext("%{count} field selected", "%{count} fields selected", selected_count(selected))

  defp included?(bundle, dep), do: Enum.any?(bundle["entries"] || [], &(&1["key"] == dep["entry_key"]))

  defp related_entries(bundle),
    do:
      bundle["dependencies"]
      |> Map.values()
      |> Enum.filter(&(&1["entry_key"] && !included?(bundle, &1)))
      |> Enum.uniq_by(& &1["entry_key"])
      |> Enum.sort_by(& &1["label"])

  defp field_label("uri"), do: gettext("URI")
  defp field_label("css_classes"), do: gettext("CSS classes")
  defp field_label("json_ld_type"), do: gettext("Structured data type")
  defp field_label("meta_title"), do: gettext("SEO title")
  defp field_label("meta_description"), do: gettext("SEO description")
  defp field_label("has_url"), do: gettext("Public URL")
  defp field_label("publish_at"), do: gettext("Publication date")
  defp field_label("sequence"), do: gettext("Order")
  defp field_label(field), do: Phoenix.Naming.humanize(field)
  defp display_field("language", value, labels), do: Map.get(labels, value, display_value(value))
  defp display_field("status", value, _) when is_binary(value), do: Phoenix.Naming.humanize(value)
  defp display_field(_, true, _), do: gettext("Yes")
  defp display_field(_, false, _), do: gettext("No")
  defp display_field(_, [], _), do: gettext("None")
  defp display_field(_, value, _), do: display_value(value)
  defp display_value(nil), do: "—"
  defp display_value(""), do: "—"
  defp display_value(value) when is_binary(value), do: value
  defp display_value(value), do: Jason.encode!(value)

  defp publication(targets, item),
    do: get_in(targets, [item.source["key"], "publication"]) || if(item.mode == "create", do: "draft", else: "preserve")

  defp selected?(selected, key, field), do: field in (get_in(selected, [key, :fields]) || [])

  defp status_label("published"), do: gettext("Published")
  defp status_label("draft"), do: gettext("Draft")
  defp status_label("pending"), do: gettext("Pending")
  defp status_label("disabled"), do: gettext("Disabled")
  defp status_label(status), do: Phoenix.Naming.humanize(status)

  defp selected_count(selected), do: Enum.sum(Enum.map(selected, fn {_, selection} -> length(selection.fields) end))
  defp selected_target(targets, key), do: if(targets[key], do: "#{targets[key]["schema"]}:#{targets[key]["id"]}")

  defp entry_options(field, options),
    do: (field.candidates ++ List.wrap(field.destination) ++ options) |> Enum.uniq_by(& &1.key)

  defp target_fields(%{destination: nil, source: source}) do
    case Brando.Content.Transfer.Error.protect(fn -> Catalog.fields(Catalog.schema!(source["schema"])) end) do
      {:ok, fields} -> fields
      _ -> []
    end
  end

  defp target_fields(field), do: field.destination.fields

  defp upload_ready?(%{entries: [entry]} = upload),
    do: entry.done? && upload_errors(upload) == [] && upload_errors(upload, entry) == []

  defp upload_ready?(_), do: false
  defp upload_error(:too_large), do: gettext("The bundle exceeds 128 MB. Export fewer fields or omit media originals.")
  defp upload_error(:not_accepted), do: gettext("Choose a .zip content bundle.")
  defp upload_error(_), do: gettext("The upload could not be completed. Remove the file and try again.")

  defp safe_definitions?(plan),
    do: Enum.all?(plan.items, &(&1.action in [:create, :noop])) && Enum.any?(plan.items, &(&1.action == :create))

  defp dependency_status(%{action: :bundle}), do: gettext("Included entry")
  defp dependency_status(%{issue: issue}) when not is_nil(issue), do: gettext("Needs attention")
  defp dependency_status(%{action: :create}), do: gettext("Create from bundle")

  defp dependency_status(item),
    do:
      if(Enum.any?(item.suggestions, &(&1.id == item.id && &1.match == :uid)),
        do: gettext("Lineage matched"),
        else: gettext("Destination selected")
      )

  defp definition_change("code"), do: gettext("render code")
  defp definition_change("class"), do: gettext("CSS classes")
  defp definition_change("refs"), do: gettext("reference defaults")
  defp definition_change("vars"), do: gettext("variable defaults")

  defp definition_reference_label(token, reference, archive) do
    dependency = archive.bundle["dependencies"][token]
    if dependency, do: dependency["label"], else: Phoenix.Naming.humanize(reference["kind"])
  end

  defp refresh_message(%{"kind" => "image", "status" => "failed"}),
    do: gettext("Content saved; media processing needs a retry.")

  defp refresh_message(%{"kind" => "image"}), do: gettext("Media is ready or queued for processing.")
  defp refresh_message(%{"status" => "failed"}), do: gettext("Content saved; rendering needs a retry.")
  defp refresh_message(_), do: gettext("Content rendered and identifiers refreshed.")

  defp content_text([]), do: gettext("No blocks")

  defp content_text(blocks) do
    Portable.walk(blocks, fn block ->
      text =
        Enum.flat_map(block["refs"] || [], fn ref ->
          data = get_in(ref, ["data", "data"]) || %{}
          text = data["text"] || data["html"] || data["code"]
          if is_binary(text), do: [text |> Floki.parse_fragment!() |> Floki.text()], else: []
        end)

      vars =
        Enum.flat_map(block["vars"] || [], fn var ->
          if var["value"] not in [nil, ""], do: ["#{var["label"] || var["key"]}: #{var["value"]}"], else: []
        end)

      Enum.join([block["description"] || Phoenix.Naming.humanize(block["type"] || "block") | text ++ vars], "\n")
    end)
    |> Enum.join("\n\n")
    |> String.slice(0, 12_000)
  end

  defp scope_label(socket) do
    site = socket.assigns[:current_site]
    environment = socket.assigns[:current_environment]

    [site && (site.name || site.key), environment && (Map.get(environment, :name) || Map.get(environment, :key))]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" / ")
    |> case do
      "" -> Brando.config(:app_name) || gettext("Current site")
      label -> label
    end
  end
end
