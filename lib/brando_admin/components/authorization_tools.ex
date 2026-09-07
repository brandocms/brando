defmodule BrandoAdmin.Components.AuthorizationTools do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: Brando.Gettext
  alias Phoenix.LiveView.JS

  def workspace(assigns) do
    ~H"""
    <section id="authorization-tools" class="utils-authorization" aria-labelledby="authorization-tools-title">
      <header class="utils-auth-heading">
        <div>
          <h2 id="authorization-tools-title">{gettext("Authorization")}</h2>
          <p>{gettext("Prepare groups, review permissions, and transfer configuration between environments.")}</p>
        </div>
        <span class={["utils-mode", !@legacy_mode? && "is-live"]}><i aria-hidden="true"></i>{if @legacy_mode?,
          do: gettext("Legacy roles active"),
          else: gettext("Groups active")}</span>
      </header>
      <div class="utils-cutover-note">
        <span class="utils-note-mark" aria-hidden="true">i</span>
        <p :if={@legacy_mode?}>
          {gettext("Legacy roles remain active until you deploy the switch to group authorization.")}
        </p>
        <p :if={!@legacy_mode?}>
          {gettext("Group authorization is enabled. Imported permissions apply immediately to existing members.")}
        </p>
      </div>
      <div class="utils-migration-steps">
        <article>
          <span class="utils-step-number">01 <span :if={@report} aria-label={gettext("Report available")}>✓</span></span>
          <h3>{gettext("Migration report")}</h3>
          <p>{gettext("Inspect accounts, site assignments, and legacy application rules.")}</p>
          <div class="utils-actions">
            <button class="utils-button" type="button" phx-click="authorization_report" disabled={@busy != nil}>
              {cond do
                @busy == "report" -> gettext("Inspecting…")
                @report -> gettext("Refresh report")
                true -> gettext("Run migration report")
              end}
            </button>
          </div>
        </article>
        <article>
          <span class="utils-step-number">02 <span :if={@backfilled?} aria-label={gettext("Groups prepared")}>✓</span></span>
          <h3>{gettext("Prepare groups")}</h3>
          <p>{gettext("Create default groups and map legacy roles to memberships. Existing changes are preserved.")}</p>
          <div class="utils-actions">
            <button class="utils-button" type="button" phx-click="authorization_backfill" disabled={@busy != nil || !@report}>
              {if @busy == "backfill", do: gettext("Preparing…"), else: gettext("Prepare groups")}
            </button>
          </div>
        </article>
        <article>
          <span class="utils-step-number">03</span>
          <h3>{gettext("Group review")}</h3>
          <p>{gettext("Review and edit group permissions and memberships before enabling group authorization.")}</p>
          <div class="utils-actions">
            <a
              class="utils-button"
              href={if @scope.kind == :installation, do: "/admin/groups?scope=installation", else: "/admin/groups"}
            >{gettext("Review groups")}</a>
          </div>
        </article>
      </div>
      <p :if={@busy} class="utils-feedback" role="status" aria-live="polite">
        {gettext("Processing migration…")}
      </p>
      <p :if={@message} class="utils-feedback success" role="status" aria-live="polite">{@message}</p>
      <p :if={@error} class="utils-feedback error" role="alert">{@error}</p>
      <section :if={@report} id="authorization-migration-report" class="utils-report" aria-labelledby="migration-report-title">
        <div class="utils-report-heading">
          <h3 id="migration-report-title">{gettext("Migration report")}</h3><span class="utils-eyebrow">{gettext(
            "Installation-wide · %{mode}",
            mode: @report.mode
          )}</span>
        </div>
        <dl class="utils-report-stats">
          <div>
            <dd>{@report.users}</dd><dt>{gettext("Accounts")}</dt>
          </div>
          <div>
            <dd>{@report.superusers}</dd><dt>{gettext("Superusers")}</dt>
          </div>
          <div>
            <dd>{@report.assignments}</dd><dt>{gettext("Site assignments")}</dt>
          </div>
          <div class={@report.unassigned_user_ids != [] && "needs-review"}>
            <dd>{length(@report.unassigned_user_ids)}</dd><dt>{gettext("Unassigned accounts")}</dt>
          </div>
        </dl>
        <p :if={@report.unassigned_user_ids != []} class="utils-feedback warning">
          {gettext("These accounts have no site assignment and will receive no site access: %{ids}.",
            ids: Enum.join(@report.unassigned_user_ids, ", ")
          )}
        </p>
        <details class="utils-rules" open>
          <summary>
            <span>{gettext("Application rules")}</span><span class="utils-pill">{@report.application_rules.review_count} {gettext(
              "to review"
            )}</span>
          </summary>
          <div class="utils-rules-content">
            <p>
              {gettext(
                "Legacy rules are not translated automatically. Review each rule against the group grants and map custom restrictions to application policies before cutover."
              )}
            </p>
            <code class="utils-module-name">{@report.application_rules.module}</code>
            <p :if={!@report.application_rules.available} class="utils-feedback warning">
              {gettext(
                "The application rules module could not be inspected. Review your application’s authorization code manually."
              )}
            </p>
            <div :for={role <- @report.application_rules.roles} class="utils-rule-role">
              <h4>{String.capitalize(to_string(role.role))}</h4>
              <p :if={role.error}>{role.error}</p>
              <ul>
                <li :for={rule <- role.rules}>
                  <span class={["utils-rule-effect", rule.effect == "Cannot" && "is-deny"]}>{rule.effect}</span>
                  <code>{rule.action} {rule.subject}</code>
                  <span :if={rule.conditional} class="utils-pill conditional">{gettext("Conditional")}</span>
                  <pre :if={rule.conditions}>{rule.conditions}</pre>
                </li>
              </ul>
            </div>
          </div>
        </details>
        <div :if={@legacy_mode?} class="utils-deploy-step">
          <span class="utils-eyebrow">{gettext("Enable group authorization")}</span><code>config :brando, authorization_mode: :groups</code><p>
            {gettext(
              "Deploy this configuration only after reviewing groups, mapping application policies, and testing representative accounts."
            )}
          </p>
        </div>
      </section>
      <section class="utils-transfer" aria-labelledby="configuration-transfer-title">
        <div class="utils-transfer-heading">
          <div>
            <span class="utils-eyebrow">{gettext("Group configuration")}</span><h3 id="configuration-transfer-title">
              {gettext("Import / export")}
            </h3>
          </div>
          <div class="utils-transfer-scope">
            <span>{gettext("Scope")}</span><strong>{@scope_label}</strong><a href={
              if @scope.kind == :installation,
                do: "/admin/config/utils#authorization-tools",
                else: "/admin/config/utils?scope=installation#authorization-tools"
            }>{if @scope.kind == :installation,
              do: gettext("Switch to workspace"),
              else: gettext("Switch to installation")}</a>
          </div>
        </div>
        <div :if={!@preview} class="utils-transfer-grid">
          <article class="utils-export">
            <h4>{gettext("Export configuration")}</h4><p>
              {gettext("Download the groups and permissions in this scope as a versioned JSON file.")}
            </p>
            <div class="utils-actions">
              <button
                type="button"
                class="utils-button"
                phx-click="authorization_export"
                phx-disable-with={gettext("Preparing…")}
              >{gettext("Prepare export")}</button>
              <a :if={@download} class="utils-download" href={@download} download={"brando-groups-#{@scope.kind}.json"}>{gettext(
                "Download configuration.json"
              )}</a>
            </div>
          </article>
          <form
            id="authorization-import-form"
            class="utils-import"
            phx-change="authorization_validate"
            phx-submit="authorization_preview"
          >
            <h4>{gettext("Import configuration")}</h4><p>
              {gettext("Upload a JSON export to review changes before applying them.")}
            </p>
            <div class="utils-dropzone" phx-drop-target={@uploads.authorization_config.ref}>
              <label for={@uploads.authorization_config.ref}>{gettext("Choose a JSON file")}<span>{gettext(
                "or drop it here · up to 1 MB"
              )}</span></label>
              <.live_file_input upload={@uploads.authorization_config} aria-label={gettext("Group configuration JSON file")} />
            </div>
            <div :for={entry <- @uploads.authorization_config.entries} class="utils-upload-entry">
              <span>{entry.client_name}</span><button
                type="button"
                phx-click="authorization_cancel_upload"
                phx-value-ref={entry.ref}
                aria-label={gettext("Remove file")}
              >×</button><progress :if={entry.progress > 0 && entry.progress < 100} value={entry.progress} max="100">{entry.progress}%</progress>
            </div>
            <p :for={error <- upload_errors(@uploads.authorization_config)} class="utils-upload-error" role="alert">
              {upload_error(error)}
            </p>
            <p
              :for={
                error <-
                  Enum.flat_map(@uploads.authorization_config.entries, &upload_errors(@uploads.authorization_config, &1))
              }
              class="utils-upload-error"
              role="alert"
            >
              {upload_error(error)}
            </p>
            <div class="utils-actions">
              <button
                type="submit"
                class="utils-button"
                disabled={@uploads.authorization_config.entries == []}
                phx-disable-with={gettext("Reading file…")}
              >{gettext("Preview import")}</button>
            </div>
          </form>
        </div>
        <section
          :if={@preview}
          id="authorization-import-preview"
          class="utils-import-preview"
          aria-labelledby="import-preview-title"
        >
          <div class="utils-preview-heading">
            <h4 id="import-preview-title" tabindex="-1" phx-mounted={JS.focus()}>{gettext("Import preview")}</h4><button
              type="button"
              class="utils-button quiet"
              phx-click="authorization_cancel_preview"
            >{gettext("Cancel")}</button>
          </div>
          <div class="utils-preview-totals">
            <span class="utils-pill mint">{@preview.created} {gettext("new")}</span><span class="utils-pill conditional">{@preview.updated} {gettext(
              "updated"
            )}</span><span class="utils-pill">{@preview.unchanged} {gettext("unchanged")}</span><span>{gettext(
              "%{count} existing members affected",
              count: @preview.members
            )}</span>
          </div>
          <p :if={@preview.changes == []}>{gettext("This file contains no groups to import.")}</p>
          <details :for={change <- @preview.changes} class="utils-import-change">
            <summary>
              <span><strong>{change.entry["name"]}</strong><code>{change.entry["key"]}</code></span><span class="utils-change-counts"><span class="utils-pill">{action_label(
                change.action
              )}</span><span class="utils-added">+{length(change.added)}</span><span class="utils-removed">−{length(
                change.removed
              )}</span><span class="utils-disclosure" aria-hidden="true"></span></span>
            </summary>
            <div class="utils-change-details">
              <dl>
                <div :if={change.before && change.before["name"] != change.entry["name"]}>
                  <dt>{gettext("Name")}</dt><dd><s>{change.before["name"]}</s> {change.entry["name"]}</dd>
                </div><div>
                  <dt>{gettext("Description")}</dt><dd>
                    <s :if={change.before && change.before["description"] != change.entry["description"]}>{change.before[
                      "description"
                    ]}</s> {change.entry["description"] || gettext("No description")}
                  </dd>
                </div>
              </dl>
              <div class="utils-grant-diff">
                <div>
                  <h5>{gettext("Permissions added")}</h5><p :if={change.added == []}>{gettext("None")}</p><ul
                    tabindex="0"
                    aria-label={gettext("Permissions added")}
                  >
                    <li :for={key <- change.added}><code>{key}</code></li>
                  </ul>
                </div><div>
                  <h5>{gettext("Permissions removed")}</h5><p :if={change.removed == []}>{gettext("None")}</p><ul
                    tabindex="0"
                    aria-label={gettext("Permissions removed")}
                  >
                    <li :for={key <- change.removed}><code>{key}</code></li>
                  </ul>
                </div>
              </div>
            </div>
          </details>
          <div class="utils-apply-bar">
            <p>
              {if @legacy_mode?,
                do: gettext("Legacy roles remain active until group authorization is enabled."),
                else: gettext("Updated grants will apply immediately to existing members.")}
            </p><button
              type="button"
              class="utils-button primary"
              phx-click="authorization_apply"
              phx-disable-with={gettext("Importing…")}
              disabled={@preview.created + @preview.updated == 0}
            >{gettext("Apply configuration")}</button>
          </div>
        </section>
        <footer class="utils-transfer-note">
          <p>
            {gettext(
              "Matching group keys are updated; other groups are preserved. Accounts, memberships, and the protected Superuser are excluded."
            )}
          </p>
        </footer>
      </section>
    </section>
    """
  end

  defp action_label(:create), do: gettext("New group")
  defp action_label(:update), do: gettext("Update")
  defp action_label(:unchanged), do: gettext("Unchanged")
  defp upload_error(:too_large), do: gettext("The file is too large. Choose a JSON file under 1 MB.")
  defp upload_error(:not_accepted), do: gettext("Choose a file with the .json extension.")
  defp upload_error(:too_many_files), do: gettext("Choose one configuration file at a time.")
  defp upload_error(_), do: gettext("The file could not be uploaded. Remove it and try again.")
end
