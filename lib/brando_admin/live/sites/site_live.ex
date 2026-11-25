defmodule BrandoAdmin.Sites.SiteLive do
  @moduledoc false

  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  # Creating, activating, deleting, suspending or archiving a site, giving or
  # taking someone's access to it, choosing which sites share the video
  # providers' libraries, and changing its languages ask for the password, a
  # code or a passkey when the session has not confirmed lately. Activating
  # puts the site's hosts back in public routing; creating one seeds its
  # groups and grants; a new default language moves the site's public URLs.
  on_mount(
    {BrandoAdmin.Reauth,
     events:
       ~w(create_site activate_site delete suspend archive grant revoke set_library_group save_languages save_delivery save_deploy_targets)}
  )

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Repo
  alias Brando.Sites.DeployConfig
  alias Brando.Sites.Site
  alias Brando.Sites.Usage
  alias Brando.Sites.Usage.Day
  alias Brando.Sites.Usage.Measure
  alias Brando.SSG.LocalDelivery
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup
  alias Brando.Users.User
  alias Brando.Worker.SiteLanguageSeed
  alias Brando.Worker.SiteUsage
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Primitives
  alias BrandoAdmin.Components.Workspace
  alias Phoenix.LiveView.AsyncResult

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    cond do
      Brando.Tenant.mode() != :multi or not superuser?(socket.assigns.current_user) ->
        {:ok, redirect(socket, to: "/admin")}

      connected?(socket) ->
        seeder = Brando.Tenant.Seeder.configured()
        # Measurements as they land, for a superuser, who alone sees them
        if Boundary.superuser?(socket.assigns.current_user), do: Usage.subscribe_overview()

        {:ok,
         socket
         |> assign(:socket_connected, true)
         |> assign(:page_title, gettext("Sites"))
         |> assign(:seeder, seeder)
         |> assign(:demo_option?, Brando.Tenant.Seeder.demo_option?(seeder))
         |> assign(:selected, nil)
         |> assign_create_form(default_create_params(), [])
         |> refresh()
         |> assign_usage()}

      true ->
        {:ok, assign(socket, :socket_connected, false)}
    end
  end

  # The selected site is in the URL: `?site=<key>`, or `?new` for the create
  # form. Without one, or with a key no site has, the admin's current site,
  # else the first.
  @impl Phoenix.LiveView
  def handle_params(params, _uri, %{assigns: %{socket_connected: true}} = socket) do
    {:noreply, socket |> assign(:selected, selection(params, socket.assigns)) |> usage_days()}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp selection(%{"new" => _}, _assigns), do: :new

  defp selection(params, %{sites: sites} = assigns) do
    current_key = assigns[:current_site] && assigns.current_site.key

    site =
      Enum.find(sites, &(&1.key == params["site"])) ||
        Enum.find(sites, &(&1.key == current_key)) ||
        List.first(sites)

    if site, do: site.id, else: :new
  end

  @impl Phoenix.LiveView
  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :site, Enum.find(assigns.sites, &(&1.id == assigns.selected)))

    ~H"""
    <div class="admin-workspace settings-workspace site-workspace">
      <Workspace.header
        eyebrow={gettext("System")}
        title={gettext("Sites")}
        subtitle={gettext("Provision isolated sites, control lifecycle, and assign users")}
      >
        <button type="button" class="btn" phx-click="refresh">{gettext("Refresh")}</button>
      </Workspace.header>

      <div class="site-layout">
        <nav class="site-list" aria-label={gettext("Choose a site")}>
          <h2 class="site-list-heading">
            {gettext("Sites")} <span class="badge badge--count">{length(@sites)}</span>
          </h2>
          <.link
            :for={site <- @sites}
            id={"site-list-#{site.id}"}
            patch={"/admin/sites?site=#{site.key}"}
            class="site-list-item"
            aria-current={@selected == site.id && "page"}
          >
            <span class="site-list-name">
              <strong>{site.name}</strong>
              <small>{site.key}</small>
              <.usage_summary
                :if={@usage && @usage.table?}
                id={"site-list-usage-#{site.id}"}
                summary={@usage.overview[site.id]}
              />
            </span>
            <.status_badge status={site.status} />
          </.link>
          <.link
            id="site-list-new"
            patch="/admin/sites?new"
            class="site-list-item site-list-new"
            aria-current={@selected == :new && "page"}
          >
            <.icon name="plus" />
            <span>{gettext("New site")}</span>
          </.link>
        </nav>

        <div class="brando-form site-detail">
          <.create_form :if={@selected == :new} form={@create_form} demo_option?={@demo_option?} seeder={@seeder} />
          <.site_form
            :if={@site}
            site={@site}
            sites={@sites}
            stats={@stats}
            seeding={@seeding}
            assignments={@assignments}
            users={@users}
            drafts={@drafts}
            superuser?={@superuser?}
            usage={@usage}
            usage_free={@usage_free}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={["badge", status_tone(@status)]}>
      <span :if={@status == :active} class="badge-dot"></span>
      {status_label(@status)}
    </span>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :demo_option?, :boolean, required: true
  attr :seeder, :atom, required: true

  defp create_form(assigns) do
    ~H"""
    <section id="site-new" class="site-editor" aria-labelledby="site-new-title">
      <header class="site-editor-heading">
        <div>
          <h2 id="site-new-title">{gettext("New site")}</h2>
          <p>
            {gettext("Creates Production and Staging schemas, seeds initial content, and grants you site admin access.")}
          </p>
        </div>
      </header>

      <form id="create-site-form" phx-change="check_create" phx-submit="create_site">
        <section class="site-section">
          <header class="site-section-heading">
            <h3>{gettext("Site")}</h3>
          </header>
          <div class="site-fields site-fields--two">
            <Input.text field={@form[:name]} label={gettext("Name")} placeholder={gettext("Acme Corporation")} />
            <Input.text
              field={@form[:key]}
              label={gettext("Key")}
              placeholder="acme"
              opts={[monospace: true]}
              instructions={
                gettext("Lowercase letters, digits and single dashes. It names the site’s database schemas and folders.")
              }
            />
          </div>
        </section>

        <.languages_fields form={@form} />

        <section class="site-section">
          <header class="site-section-heading">
            <h3>{gettext("Delivery")}</h3>
            <p>{gettext("How visitors get the site’s pages. It can be changed later.")}</p>
          </header>
          <div class="site-fields site-fields--two">
            <Primitives.field_base
              field={@form[:delivery_mode]}
              label={gettext("Mode")}
              instructions={
                gettext("Dynamic is served directly by Phoenix. Static requires a configured SSG build and deploy pipeline.")
              }
            >
              <:value>{delivery_label(@form[:delivery_mode].value)}</:value>
              <select id={@form[:delivery_mode].id} name={@form[:delivery_mode].name} class="admin-select">
                <option
                  :for={mode <- Site.delivery_modes()}
                  value={mode}
                  selected={to_string(@form[:delivery_mode].value) == to_string(mode)}
                >
                  {delivery_label(mode)}
                </option>
              </select>
            </Primitives.field_base>
          </div>
        </section>

        <section class="site-section">
          <Input.checkbox
            field={@form[:demo]}
            label={gettext("Starting content")}
            opts={[text: gettext("Start with demo content"), compact: true]}
            instructions={demo_note(@demo_option?, @seeder)}
          />
        </section>

        <div class="site-actions">
          <button type="submit" class="btn btn--primary btn--lg" phx-disable-with={gettext("Provisioning…")}>
            {gettext("Create site")}
          </button>
        </div>
      </form>
    </section>
    """
  end

  # The languages as a list, and the default as a select of what is in it,
  # in the create form and a site's form alike
  attr :form, Phoenix.HTML.Form, required: true
  attr :site, Site, default: nil
  attr :removed, :list, default: []
  slot :inner_block

  defp languages_fields(assigns) do
    languages = clean_languages(assigns.form[:languages].value)

    assigns =
      assigns
      |> assign(:languages, languages)
      |> assign(:default, default_choice(assigns.form[:default_language].value, languages))

    ~H"""
    <section class="site-section">
      <header class="site-section-heading">
        <h3>{gettext("Languages")}</h3>
        <p>
          {gettext("The languages the site’s content is written in, in the order the admin lists them.")}
        </p>
      </header>
      <div class="site-fields site-fields--two">
        <Input.string_list
          field={@form[:languages]}
          label={gettext("Languages")}
          sync_insert
          instructions={
            gettext(
              "Language keys such as en or no, one per line. A language you add gets the same starting content as a new site, in each environment."
            )
          }
        />
        <Primitives.field_base
          field={@form[:default_language]}
          label={gettext("Default language")}
          instructions={gettext("The language of the site’s URLs without a language prefix.")}
        >
          <:value>{@default}</:value>
          <select
            id={@form[:default_language].id}
            name={@form[:default_language].name}
            class="admin-select"
            disabled={@languages == []}
          >
            <option :for={language <- @languages} value={language} selected={language == @default}>
              {language_label(language)}
            </option>
          </select>
        </Primitives.field_base>
      </div>
      <p :if={@removed != []} class="site-hint" role="status">
        {gettext(
          "Removing %{languages} deletes nothing: the content stays, and comes back if the language is added again.",
          languages: Enum.join(@removed, ", ")
        )}
      </p>
      <p
        :if={@site && @default && @default != @site.default_language && @languages != []}
        class="site-hint"
        role="status"
      >
        {gettext("Saving makes %{language} the default language, which moves the site’s public URLs.",
          language: @default
        )}
      </p>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :id, :string, required: true
  attr :summary, :map, default: nil

  # The site's total storage, as last measured, and its requests in the last
  # 30 days, under its name in the list
  defp usage_summary(assigns) do
    ~H"""
    <span id={@id} class="site-list-usage">
      {usage_summary_text(@summary)}
    </span>
    """
  end

  defp usage_summary_text(%{measured: %Day{} = measured, requests: requests}),
    do:
      gettext("%{storage} · %{requests} requests",
        storage: format_size(Day.storage_bytes(measured)),
        requests: format_count(requests)
      )

  defp usage_summary_text(%{requests: requests}),
    do: gettext("Not measured · %{requests} requests", requests: format_count(requests))

  defp usage_summary_text(nil), do: usage_summary_text(%{requests: 0})

  defp site_form(assigns) do
    site = assigns.site

    drafts = assigns.drafts

    assigns =
      assigns
      |> assign(:name_form, name_form(drafts, site))
      |> assign(:languages_form, languages_form(drafts, site))
      |> assign(:removed, removed_languages(drafts, site))
      |> assign(:seeding_rows, seeding(assigns.seeding, site.id))
      |> assign(:site_assignments, assignments(assigns.assignments, site.id))
      |> assign(:library_form, library_form(drafts, site))
      |> assign(:grant, Map.get(drafts, {:grant, site.id}, %{}))

    ~H"""
    <section id={"site-#{@site.id}"} class="site-editor" aria-labelledby={"site-#{@site.id}-title"}>
      <header class="site-editor-heading">
        <div>
          <h2 id={"site-#{@site.id}-title"}>{@site.name}</h2>
          <div class="site-editor-meta">
            <span class="badge badge--outline workspace-mono">{@site.key}</span>
            <.status_badge status={@site.status} />
            <span class="badge">{delivery_label(@site.delivery_mode)}</span>
          </div>
        </div>
      </header>

      <dl class="site-stats">
        <div>
          <dt>{gettext("Environments")}</dt><dd>{length(@site.environments)}</dd>
        </div>
        <div>
          <dt>{gettext("Pages")}</dt><dd>{stat(@stats, @site.id, :page_count)}</dd>
        </div>
        <div>
          <dt>{gettext("Last page edit")}</dt><dd>{format_last_edit(stat(@stats, @site.id, :last_edit))}</dd>
        </div>
      </dl>

      <form id={"name-site-#{@site.id}"} phx-change="check_name" phx-submit="save_name">
        <input type="hidden" name="site[id]" value={@site.id} />
        <section class="site-section">
          <header class="site-section-heading">
            <h3>{gettext("Site")}</h3>
          </header>
          <div class="site-fields site-fields--two">
            <Input.text field={@name_form[:name]} label={gettext("Name")} />
            <Input.text
              field={@name_form[:key]}
              label={gettext("Key")}
              opts={[monospace: true, locked: true]}
              instructions={gettext("It names the site’s database schemas and folders, so it cannot be changed.")}
            />
          </div>
          <div class="site-actions">
            <button type="submit" class="btn">{gettext("Save name")}</button>
          </div>
        </section>
      </form>

      <form
        id={"languages-site-#{@site.id}"}
        class="site-languages"
        phx-change="check_languages"
        phx-submit="save_languages"
      >
        <input type="hidden" name="site[id]" value={@site.id} />
        <.languages_fields form={@languages_form} site={@site} removed={@removed}>
          <div class="site-actions">
            <button type="submit" class="btn">{gettext("Save languages")}</button>
          </div>
        </.languages_fields>
      </form>

      <div :if={@seeding_rows != []} class="site-seeding">
        <div class="workspace-panel">
          <div class="workspace-table-scroll">
            <table id={"seeding-site-#{@site.id}"} class="workspace-table">
              <tbody>
                <tr
                  :for={row <- @seeding_rows}
                  id={"seeding-#{@site.id}-#{row.environment.id}-#{row.language}"}
                >
                  <td>
                    {seeding_status(row)}
                    <small :if={row.busy}>{gettext("Waiting for the environment's copy or setup to finish.")}</small>
                  </td>
                  <td class="row-actions">
                    <button
                      :if={seed_again?(row)}
                      type="button"
                      class="btn btn--sm"
                      phx-click="seed_language"
                      phx-value-site-id={@site.id}
                      phx-value-environment-id={row.environment.id}
                      phx-value-language={row.language}
                    >
                      {gettext("Seed again")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <.usage_section :if={@usage} site={@site} usage={@usage} free={@usage_free} />

      <.delivery_section
        site={@site}
        superuser?={@superuser?}
        draft={Map.get(@drafts, {:deploy_targets, @site.id})}
        typed={Map.get(@drafts, {:deploy_targets_typed, @site.id})}
      />

      <section class="site-section">
        <header class="site-section-heading">
          <h3>{gettext("Video provider libraries")}</h3>
          <p>{gettext("Sites with the same group key share the provider videos offered under “Add from …”.")}</p>
        </header>
        <form
          id={"library-group-site-#{@site.id}"}
          class="site-library-group"
          phx-change="check_library_group"
          phx-submit="set_library_group"
        >
          <input type="hidden" name="site[id]" value={@site.id} />
          <div class="site-fields site-fields--two">
            <Input.text
              field={@library_form[:provider_library_group]}
              label={gettext("Provider library group")}
              placeholder={gettext("Not shared")}
              opts={[monospace: true]}
              instructions={library_group_note(@sites, @site)}
            />
          </div>
          <div class="site-actions">
            <button type="submit" class="btn">{gettext("Save group")}</button>
          </div>
        </form>
      </section>

      <section class="site-section site-access">
        <header class="site-section-heading">
          <h3>{gettext("Access")}</h3>
          <p :if={!Brando.Authorization.enabled?()}>
            {gettext("Who may work on this site besides superusers, who reach every site.")}
          </p>
        </header>
        <p :if={Brando.Authorization.enabled?()}>
          <a class="btn" href={"/admin/groups?brando_site_key=#{@site.key}"}>
            {gettext("Manage this site’s groups and members")}
          </a>
        </p>
        <div :if={!Brando.Authorization.enabled?()} class="site-users">
          <p :if={@site_assignments == []} class="site-hint">{gettext("No explicit user assignments.")}</p>
          <div :if={@site_assignments != []} class="workspace-panel">
            <div class="workspace-table-scroll">
              <table class="workspace-table">
                <thead>
                  <tr>
                    <th>{gettext("User")}</th>
                    <th>{gettext("Role")}</th>
                    <th><span class="workspace-sr-only">{gettext("Actions")}</span></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={assignment <- @site_assignments} id={"assignment-#{assignment.id}"}>
                    <td>{assignment.user.name}<small>{assignment.user.email}</small></td>
                    <td><span class="badge">{role_label(assignment.role)}</span></td>
                    <td class="row-actions">
                      <button
                        type="button"
                        class="btn btn--sm btn--quiet btn--danger"
                        phx-click="revoke"
                        phx-value-site-id={@site.id}
                        phx-value-user-id={assignment.user_id}
                        data-confirm-title={gettext("Revoke %{name}’s access?", name: assignment.user.name)}
                        data-confirm={
                          gettext("%{name} can no longer open %{site} in the admin.",
                            name: assignment.user.name,
                            site: @site.name
                          )
                        }
                        data-confirm-ok={gettext("Revoke access")}
                        data-confirm-destructive
                      >
                        {gettext("Revoke")}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <h4>{gettext("Grant access")}</h4>
          <p :if={@users == []} class="site-hint">
            {gettext(
              "Every user here is a superuser, who already has access to every site. Access is granted to users with another role."
            )}
          </p>
          <form
            :if={@users != []}
            phx-change="check_grant"
            phx-submit="grant"
            id={"grant-site-#{@site.id}"}
            class="site-grant"
          >
            <input type="hidden" name="assignment[site_id]" value={@site.id} />
            <label class="site-select">
              <span>{gettext("User")}</span>
              <select name="assignment[user_id]" class="admin-select" required>
                <option :for={user <- @users} value={user.id} selected={@grant["user_id"] == to_string(user.id)}>
                  {user.name} · {user.email}
                </option>
              </select>
            </label>
            <label class="site-select">
              <span>{gettext("Role")}</span>
              <select name="assignment[role]" class="admin-select">
                <option value="editor" selected={@grant["role"] == "editor"}>{gettext("Editor")}</option>
                <option value="admin" selected={@grant["role"] == "admin"}>{gettext("Administrator")}</option>
              </select>
            </label>
            <button type="submit" class="btn btn--primary">{gettext("Grant access")}</button>
          </form>
        </div>
      </section>

      <.lifecycle_section site={@site} />
    </section>
    """
  end

  attr :site, Site, required: true
  attr :usage, :map, required: true
  attr :free, AsyncResult, default: nil

  # What the site stores and the requests the installation answered on its
  # hosts, for a superuser only (`Brando.Sites.Usage`)
  defp usage_section(%{usage: %{table?: false}} = assigns) do
    ~H"""
    <section class="site-section site-usage" id={"usage-site-#{@site.id}"}>
      <header class="site-section-heading">
        <h3>{gettext("Usage")}</h3>
      </header>
      <p class="site-hint" id={"usage-missing-#{@site.id}"}>
        {gettext("The usage table’s migration has not run on this installation yet, so there are no figures.")}
      </p>
    </section>
    """
  end

  defp usage_section(assigns) do
    usage = assigns.usage
    measured = Enum.filter(usage.days, &Day.measured?/1)
    latest = if measured == [], do: get_in(usage.overview, [assigns.site.id, :measured]), else: latest_day(measured)

    assigns =
      assigns
      |> assign(:latest, latest)
      |> assign(:change, storage_change(measured))
      |> assign(:requests, Enum.sum_by(usage.days, & &1.requests))
      |> assign(:bytes_sent, Enum.sum_by(usage.days, & &1.bytes_sent))
      |> assign(:bars, traffic_bars(usage.days, usage.today))
      |> assign(:databases, database_rows(latest, assigns.site))
      |> assign(:elsewhere, published_elsewhere(assigns.site))

    ~H"""
    <section class="site-section site-usage" id={"usage-site-#{@site.id}"}>
      <header class="site-section-heading">
        <h3>{gettext("Usage")}</h3>
        <p>
          {gettext(
            "What the site stores, measured once a day, and the requests this installation answered on the site’s hosts, per UTC day."
          )}
        </p>
      </header>

      <div class="site-usage-group" id={"usage-storage-#{@site.id}"}>
        <h4>{gettext("Storage")}</h4>
        <p :if={is_nil(@latest)} class="site-hint">
          {gettext("Not measured yet. The daily measuring, or Measure now, fills it in.")}
        </p>
        <dl :if={@latest} class="site-facts" id={"usage-storage-facts-#{@site.id}"}>
          <div>
            <dt>{gettext("Total")}</dt>
            <dd>{format_size(Day.storage_bytes(@latest))}</dd>
          </div>
          <div>
            <dt>{gettext("Media")}</dt>
            <dd>{format_size(@latest.media_bytes)}</dd>
          </div>
          <div>
            <dt>{gettext("Kept static builds")}</dt>
            <dd>{format_size(@latest.builds_bytes)}</dd>
          </div>
          <div>
            <dt>{gettext("Databases")}</dt>
            <dd>{format_size(Day.database_bytes(@latest))}</dd>
          </div>
          <div :if={@change} id={"usage-change-#{@site.id}"}>
            <dt>{gettext("Change since %{day}", day: format_day(@change.since))}</dt>
            <dd>{format_change(@change.bytes)}</dd>
          </div>
        </dl>
        <p :if={@latest} class="site-hint">
          {gettext("Measured on %{day}.", day: format_day(@latest.day))}
        </p>
        <div :if={@databases != []} class="workspace-panel site-usage-databases">
          <div class="workspace-table-scroll">
            <table class="workspace-table">
              <thead>
                <tr>
                  <th>{gettext("Database")}</th>
                  <th class="numeric">{gettext("Size")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @databases} id={"usage-db-#{@site.id}-#{row["schema"]}"}>
                  <td class={row["archive"] && "site-usage-archive"}>
                    {database_label(row)}<small class="workspace-mono">{row["schema"]}</small>
                  </td>
                  <td class="numeric">{format_size(row["bytes"])}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div class="site-usage-group" id={"usage-traffic-#{@site.id}"}>
        <h4>{gettext("Traffic, last 30 days")}</h4>
        <p :if={@elsewhere} class="site-hint" id={"usage-elsewhere-#{@site.id}"}>
          {gettext(
            "Published to %{target}. These are the requests this installation answered on the site’s hosts.",
            target: @elsewhere
          )}
        </p>
        <dl class="site-facts">
          <div>
            <dt>{gettext("Requests")}</dt>
            <dd>{format_count(@requests)}</dd>
          </div>
          <div>
            <dt>{gettext("Bytes served")}</dt>
            <dd>{format_size(@bytes_sent)}</dd>
          </div>
        </dl>
        <figure class="site-usage-trend">
          <svg
            viewBox="0 0 300 48"
            preserveAspectRatio="none"
            role="img"
            aria-label={gettext("Requests per day, the last 30 days")}
          >
            <rect
              :for={bar <- @bars}
              x={bar.x}
              y={48 - bar.height}
              width="8"
              height={bar.height}
              rx="1"
            >
              <title>{bar.title}</title>
            </rect>
          </svg>
          <figcaption>
            <span>{format_day(Date.add(@usage.today, -29))}</span>
            <span>{format_day(@usage.today)}</span>
          </figcaption>
        </figure>
      </div>

      <div class="site-usage-group" id={"usage-installation-#{@site.id}"}>
        <h4>{gettext("Installation")}</h4>
        <dl class="site-facts">
          <div>
            <dt>{gettext("All measured sites")}</dt>
            <dd>{format_size(@usage.total)}</dd>
          </div>
          <div>
            <dt>{gettext("Free on the media volume")}</dt>
            <dd id={"usage-free-#{@site.id}"}>{free_space(@free)}</dd>
          </div>
        </dl>
        <p class="site-hint">
          {gettext(
            "The free space is that of the volume holding %{path}. Databases on another volume count in the total, not in the free space.",
            path: @usage.media_path
          )}
        </p>
      </div>

      <div class="site-actions">
        <button type="button" id={"measure-usage-#{@site.id}"} class="btn" phx-click="measure_usage" phx-value-id={@site.id}>
          {gettext("Measure now")}
        </button>
      </div>
    </section>
    """
  end

  # Read after the first render: `df` may take seconds on a slow volume
  defp free_space(%AsyncResult{ok?: true, result: bytes}) when is_integer(bytes), do: format_size(bytes)
  defp free_space(%AsyncResult{loading: loading}) when not is_nil(loading), do: "…"
  defp free_space(_unknown), do: gettext("Unknown")

  # From the first to the last measurement of the 30 days: none without two
  defp storage_change([first, _ | _] = measured) do
    last = latest_day(measured)
    %{since: first.day, bytes: Day.storage_bytes(last) - Day.storage_bytes(first)}
  end

  defp storage_change(_measured), do: nil

  defp latest_day(days), do: Enum.max_by(days, & &1.day, Date)

  # 30 bars of requests per day, the busiest at full height
  defp traffic_bars(days, today) do
    by_day = Map.new(days, &{&1.day, &1.requests})
    dates = Enum.map(29..0//-1, &Date.add(today, -&1))
    peak = dates |> Enum.map(&Map.get(by_day, &1, 0)) |> Enum.max()

    dates
    |> Enum.with_index()
    |> Enum.map(fn {date, index} ->
      requests = Map.get(by_day, date, 0)

      %{
        x: index * 10 + 1,
        height: bar_height(requests, peak),
        title: gettext("%{day}: %{requests} requests", day: format_day(date), requests: format_count(requests))
      }
    end)
  end

  # A day with requests is at least a pixel high
  defp bar_height(0, _peak), do: 0
  defp bar_height(requests, peak), do: max(round(requests / peak * 48), 1)

  # Each environment's database, its archives under it, newest first; an
  # archive of an environment the site no longer has after those that it has
  defp database_rows(nil, _site), do: []

  defp database_rows(%Day{databases: databases}, site) do
    order = site.environments |> Enum.with_index() |> Map.new(fn {environment, index} -> {environment.key, index} end)

    databases
    |> List.wrap()
    |> Enum.sort_by(fn row ->
      {Map.get(order, row["environment"], map_size(order)), row["environment"] || "", row["archive"],
       if(row["archive"], do: invert(row["schema"]), else: "")}
    end)
  end

  defp invert(schema), do: schema |> String.to_charlist() |> Enum.map(&(0x10FFFF - &1))

  defp database_label(%{"archive" => true}), do: pgettext("database", "Archive")
  defp database_label(%{"environment" => nil}), do: gettext("Unknown environment")
  defp database_label(%{"environment" => environment}), do: environment

  # A static site deployed to another host: its public traffic goes there
  defp published_elsewhere(%Site{delivery_mode: :static, deploy_config: %DeployConfig{strategy: strategy}} = site)
       when strategy in [:rsync, :s3, :cloudflare_pages],
       do: strategy_label(site.deploy_config)

  defp published_elsewhere(_site), do: nil

  attr :site, Site, required: true
  attr :superuser?, :boolean, required: true
  attr :draft, :map, default: nil
  attr :typed, :map, default: nil

  defp delivery_section(assigns) do
    target = other_delivery(assigns.site.delivery_mode)

    assigns =
      assign(assigns,
        target: target,
        effect: delivery_effect(assigns.site, target),
        state: Setup.delivery_state(assigns.site)
      )

    ~H"""
    <section class="site-section" id={"delivery-site-#{@site.id}"}>
      <header class="site-section-heading">
        <h3>{gettext("Delivery")}</h3>
        <p>{delivery_description(@site.delivery_mode)}</p>
      </header>
      <dl class="site-facts">
        <div>
          <dt>{gettext("Mode")}</dt>
          <dd>{delivery_label(@site.delivery_mode)}</dd>
        </div>
        <div :if={@site.delivery_mode == :static}>
          <dt>{gettext("Deploys to")}</dt>
          <dd>{strategy_label(@site.deploy_config)}</dd>
        </div>
        <div :if={Site.local_delivery?(@site)}>
          <dt>{gettext("Published build")}</dt>
          <dd>{@site.published_build || gettext("None yet")}</dd>
        </div>
      </dl>
      <div class="site-actions">
        <button
          type="button"
          id={"delivery-switch-#{@site.id}"}
          class="btn"
          phx-click="save_delivery"
          phx-value-id={@site.id}
          phx-value-mode={@target}
          phx-value-delivery={@state["delivery"]}
          phx-value-strategy={@state["strategy"]}
          phx-value-build={@state["build"]}
          phx-value-status={@state["status"]}
          data-confirm-title={switch_title(@site, @target)}
          data-confirm={@effect}
          data-confirm-ok={switch_label(@target)}
        >
          {switch_label(@target)}
        </button>
      </div>
      <.deploy_targets :if={@superuser? and deploy_targets_shown?(@site)} site={@site} draft={@draft} typed={@typed} />
    </section>
    """
  end

  # Only a static site deploys. One that is dynamic now shows them while it
  # still has entries, so what it may deploy to is never out of sight.
  defp deploy_targets_shown?(%Site{delivery_mode: :static}), do: true
  defp deploy_targets_shown?(%Site{allowed_rsync_targets: rsync, allowed_s3_targets: s3}), do: rsync != [] or s3 != []

  attr :site, Site, required: true
  attr :draft, :map, default: nil
  attr :typed, :map, default: nil

  # The deploy targets a superuser allows the site besides config's
  # (`Brando.Tenant.Registry.update_site_deploy_targets/4`), shown only to a
  # superuser in either authorization mode: in groups mode, reading this
  # screen takes no more than the Sites read permission
  defp deploy_targets(assigns) do
    site = assigns.site

    assigns =
      assigns
      |> assign(:form, deploy_targets_form(assigns.draft, site))
      |> assign(:configured_rsync, DeployConfig.configured_entries(:rsync_targets, site.key))
      |> assign(:configured_s3, DeployConfig.configured_entries(:s3_targets, site.key))
      |> assign(:refused_target, refused_target(site))

    ~H"""
    <form
      id={"deploy-targets-site-#{@site.id}"}
      class="site-deploy-targets"
      phx-change="check_deploy_targets"
      phx-submit="save_deploy_targets"
    >
      <input type="hidden" name="deploy_targets[id]" value={@site.id} />
      <input type="hidden" name="deploy_targets[base]" value={@form[:base].value} />
      <header class="site-subsection-heading">
        <h4>{gettext("Allowed deploy targets")}</h4>
        <p>
          {gettext(
            "Where the site’s deploys may go, besides what this installation’s config allows. Its administrators choose a target on the Publishing screen, but cannot change this list. Each entry is an exact destination, or a parent ending in / that allows everything under it, not the parent itself."
          )}
        </p>
      </header>
      <p :if={@typed} class="site-hint site-hint--warning" role="status">
        {gettext(
          "The lists were changed elsewhere while you edited them, so nothing was saved, and they now show what is saved. What you had: rsync %{rsync}; S3 %{s3}.",
          rsync: typed_entries(@typed["allowed_rsync_targets"]),
          s3: typed_entries(@typed["allowed_s3_targets"])
        )}
      </p>
      <p :if={@refused_target} class="site-hint site-hint--warning" role="status">
        {gettext(
          "The site’s saved target, %{target}, is not allowed here or in config: its next deploy will be refused.",
          target: @refused_target
        )}
      </p>
      <div class="site-fields site-fields--two">
        <div class="site-target-list">
          <Input.string_list
            field={@form[:allowed_rsync_targets]}
            label={gettext("Allowed rsync targets")}
            sync_insert
            instructions={
              gettext(
                "For example deploy@static.example.com:/srv/sites/acme, or deploy@static.example.com:/srv/sites/ for every directory under it."
              )
            }
          />
          <.configured_targets entries={@configured_rsync} />
        </div>
        <div class="site-target-list">
          <Input.string_list
            field={@form[:allowed_s3_targets]}
            label={gettext("Allowed S3 targets")}
            sync_insert
            instructions={gettext("For example s3://acme-www, or s3://static-bucket/sites/ for every prefix under it.")}
          />
          <.configured_targets entries={@configured_s3} />
        </div>
      </div>
      <div class="site-actions">
        <button type="submit" class="btn">{gettext("Save deploy targets")}</button>
      </div>
    </form>
    """
  end

  attr :entries, :list, required: true

  defp configured_targets(assigns) do
    ~H"""
    <div class="site-configured-targets">
      <span class="site-configured-label">{gettext("Allowed by config")}</span>
      <ul :if={@entries != []}>
        <li :for={entry <- @entries} class="workspace-mono">{entry}</li>
      </ul>
      <span :if={@entries == []} class="site-hint">{gettext("None")}</span>
    </div>
    """
  end

  # The draft keeps the rows as typed, blank ones included, a refused save's
  # errors, and the digest of the stored lists it was started from, which
  # the save posts back (`Brando.Sites.Site.deploy_targets_digest/1`)
  defp deploy_targets_form(nil, site) do
    to_form(
      %{
        "allowed_rsync_targets" => site.allowed_rsync_targets,
        "allowed_s3_targets" => site.allowed_s3_targets,
        "base" => Site.deploy_targets_digest(site)
      },
      as: "deploy_targets",
      id: "deploy-targets-site-#{site.id}"
    )
  end

  defp deploy_targets_form(%{rows: rows, base: base, errors: errors}, site),
    do: to_form(Map.put(rows, "base", base), as: "deploy_targets", id: "deploy-targets-site-#{site.id}", errors: errors)

  defp typed_entries(entries) do
    case Brando.Type.StringList.normalize(entries || []) do
      [] -> gettext("none")
      entries -> Enum.join(entries, ", ")
    end
  end

  # A target the site saved that neither its list nor config allows now
  defp refused_target(
         %Site{delivery_mode: :static, deploy_config: %DeployConfig{strategy: strategy, target: target}} = site
       )
       when strategy in [:rsync, :s3] and is_binary(target) do
    if not DeployConfig.allowed_target?(strategy, target, site), do: target
  end

  defp refused_target(_site), do: nil

  attr :site, Site, required: true

  defp lifecycle_section(assigns) do
    ~H"""
    <section class="site-section site-lifecycle" id={"lifecycle-site-#{@site.id}"}>
      <header class="site-section-heading">
        <h3>{gettext("Lifecycle")}</h3>
        <p>{lifecycle_description(@site)}</p>
      </header>
      <div class="site-actions">
        <button
          :if={@site.status == :active}
          type="button"
          class="btn"
          phx-click="suspend"
          phx-value-id={@site.id}
          data-confirm-title={gettext("Suspend %{name}?", name: @site.name)}
          data-confirm={gettext("Its domains stop serving until the site is activated again. Nothing is deleted.")}
          data-confirm-ok={gettext("Suspend")}
        >
          {gettext("Suspend")}
        </button>
        <button
          :if={@site.status == :suspended}
          type="button"
          class="btn btn--primary"
          phx-click="activate_site"
          phx-value-id={@site.id}
          data-confirm-title={gettext("Activate %{name}?", name: @site.name)}
          data-confirm={activation_effect(@site)}
          data-confirm-ok={gettext("Activate")}
        >
          {gettext("Activate")}
        </button>
        <button
          :if={@site.status != :archived}
          type="button"
          class="btn btn--danger"
          phx-click="archive"
          phx-value-id={@site.id}
          data-confirm-title={gettext("Archive %{name}?", name: @site.name)}
          data-confirm={gettext("Archive %{name}? Its domains will stop serving immediately.", name: @site.name)}
          data-confirm-ok={gettext("Archive")}
          data-confirm-destructive
        >
          {gettext("Archive")}
        </button>
        <button
          :if={@site.status == :archived}
          type="button"
          class="btn"
          phx-click="activate_site"
          phx-value-id={@site.id}
          data-confirm-title={gettext("Restore %{name}?", name: @site.name)}
          data-confirm={activation_effect(@site)}
          data-confirm-ok={gettext("Restore")}
        >
          {gettext("Restore")}
        </button>
        <button
          :if={@site.status == :archived}
          type="button"
          class="btn btn--danger btn--primary"
          phx-click="delete"
          phx-value-id={@site.id}
          data-confirm-title={gettext("Permanently delete %{name}?", name: @site.name)}
          data-confirm={gettext("Permanently delete %{name}, all schemas, media, and uploaded assets?", name: @site.name)}
          data-confirm-ok={gettext("Permanently delete")}
          data-confirm-destructive
        >
          {gettext("Permanently delete")}
        </button>
      </div>
    </section>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket), do: {:noreply, refresh(socket)}

  # The text fields' `Brando.FieldBase` hook reports focus and blur to the
  # nearest `.brando-form`, for field presence, which this screen has none of
  def handle_event(event, _params, socket) when event in ["focus", "blur"], do: {:noreply, socket}

  def handle_event("check_create", %{"site" => params}, socket) do
    {:noreply, assign_create_form(socket, params, [])}
  end

  def handle_event("create_site", %{"site" => params}, socket) do
    attrs = %{
      name: params["name"],
      key: params["key"],
      languages: clean_languages(params["languages"]),
      default_language: params["default_language"],
      status: :active,
      delivery_mode: parse_delivery_mode(params["delivery_mode"])
    }

    demo = params["demo"] != "false"

    case Setup.create_site(attrs, socket.assigns.current_user, demo: demo) do
      {:ok, site} ->
        {:noreply,
         socket
         |> notify(created_message(site, demo, socket.assigns))
         |> assign_create_form(default_create_params(), [])
         |> refresh()
         |> push_patch(to: site_path(site))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign_create_form(params, changeset_errors(reason))
         |> notify_error(lifecycle_error(reason))}
    end
  end

  # Each form's draft: what it shows until saved, as a change re-renders the
  # site's form, and a field that is not focused takes the rendered value.
  # The languages keep their blank rows, which the list's rows are matched
  # by, until they are saved.
  def handle_event("check_languages", %{"site" => params}, socket) do
    put_draft(socket, :languages, params["id"], %{
      languages: List.wrap(params["languages"]),
      default_language: params["default_language"]
    })
  end

  def handle_event("check_name", %{"site" => params}, socket),
    do: put_draft(socket, :name, params["id"], params["name"])

  def handle_event("check_library_group", %{"site" => params}, socket),
    do: put_draft(socket, :library, params["id"], params["provider_library_group"])

  def handle_event("check_grant", %{"assignment" => params}, socket),
    do: put_draft(socket, :grant, params["site_id"], Map.take(params, ["user_id", "role"]))

  def handle_event("save_name", %{"site" => params}, socket) do
    with {:ok, site} <- site_from_socket(socket, params["id"]),
         {:ok, site} <- Setup.update_name(site, params["name"], socket.assigns.current_user) do
      {:noreply,
       socket
       |> drop_draft(:name, site.id)
       |> notify(gettext("%{name} saved.", name: site.name))
       |> refresh()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  def handle_event("save_languages", %{"site" => params}, socket) do
    attrs = %{languages: clean_languages(params["languages"]), default_language: params["default_language"]}

    with {:ok, site} <- site_from_socket(socket, params["id"]),
         {:ok, site} <- Setup.update_languages(site, attrs, socket.assigns.current_user) do
      {:noreply,
       socket
       |> drop_draft(:languages, site.id)
       |> notify(gettext("Languages for %{name} saved.", name: site.name))
       |> refresh()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  # The confirmation was written for the delivery the button carries: a
  # deploy or another switch since then is refused, and the form shows the
  # site as it is now
  def handle_event("save_delivery", %{"id" => id, "mode" => mode} = params, socket) do
    # An empty value may arrive as no value at all
    expected = Map.new(~w(delivery strategy build status), &{&1, params[&1] || ""})

    with {:ok, site} <- site_from_socket(socket, id),
         {:ok, mode} <- delivery_mode_param(mode),
         {:ok, site} <- Setup.update_delivery(site, mode, socket.assigns.current_user, expected: expected) do
      {:noreply,
       socket
       |> notify(gettext("%{name} now has %{delivery} delivery.", name: site.name, delivery: delivery_name(mode)))
       |> refresh()}
    else
      {:error, :delivery_changed} ->
        {:noreply, socket |> refresh() |> notify_error(delivery_changed_message(socket, id))}

      {:error, reason} ->
        {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  # Like the languages, the lists keep their blank rows until saved. A draft
  # that is the lists it was started from is dropped, so the form shows the
  # stored lists again, as they are now.
  def handle_event("check_deploy_targets", %{"deploy_targets" => params}, socket) do
    with :ok <- deploy_targets_access(socket),
         {:ok, site} <- site_from_socket(socket, params["id"]) do
      rows = deploy_target_rows(params)

      if Site.deploy_targets_digest(trailing_trimmed(rows)) == params["base"],
        do: {:noreply, drop_draft(socket, :deploy_targets, site.id)},
        else: put_draft(socket, :deploy_targets, site.id, %{rows: rows, base: params["base"], errors: []})
    else
      {:error, :site_not_found} -> {:noreply, socket}
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  # The form posts both lists whole, and the digest of the stored lists it
  # was drawn from: lists changed elsewhere since are not overwritten
  def handle_event("save_deploy_targets", %{"deploy_targets" => params}, socket) do
    rows = deploy_target_rows(params)
    user = socket.assigns.current_user

    with :ok <- deploy_targets_access(socket),
         {:ok, site} <- site_from_socket(socket, params["id"]),
         {:ok, site} <- Registry.update_site_deploy_targets(site, rows, user, expected: params["base"] || "") do
      {:noreply,
       socket
       |> drop_draft(:deploy_targets, site.id)
       |> drop_draft(:deploy_targets_typed, site.id)
       |> notify(gettext("Deploy targets for %{name} saved.", name: site.name))
       |> refresh()}
    else
      {:error, :deploy_targets_changed} ->
        {:ok, site} = site_from_socket(socket, params["id"])

        {:noreply,
         socket
         |> drop_draft(:deploy_targets, site.id)
         |> update(:drafts, &Map.put(&1, {:deploy_targets_typed, site.id}, rows))
         |> refresh()
         |> notify_error(
           gettext("%{name}’s deploy targets were changed elsewhere, so nothing was saved.", name: site.name)
         )}

      {:error, %Ecto.Changeset{data: site, errors: errors}} ->
        draft = %{rows: rows, base: params["base"], errors: errors}

        {:noreply,
         socket
         |> update(:drafts, &Map.put(&1, {:deploy_targets, site.id}, draft))
         |> notify_error(gettext("Some deploy targets were refused. Nothing was saved."))}

      {:error, reason} ->
        {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  # Only a superuser sees usage or measures it: in groups mode, reading this
  # screen takes only the Sites read permission
  def handle_event("measure_usage", %{"id" => id}, socket) do
    with :ok <- usage_access(socket),
         {:ok, site} <- site_from_socket(socket, id),
         {:ok, _job} <- SiteUsage.measure_now(site) do
      {:noreply, notify(socket, gettext("Measuring %{name} is queued.", name: site.name))}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  def handle_event("seed_language", params, socket) do
    with {:ok, site} <- site_from_socket(socket, params["site-id"]),
         {:ok, environment} <- environment_of(site, params["environment-id"]),
         true <- params["language"] in site.languages || {:error, {:language_not_on_site, site, params["language"]}},
         :ok <- authorize_site_update(socket),
         :ok <- ready(site) do
      :ok =
        SiteLanguageSeed.enqueue(site, params["language"], socket.assigns.current_user, environment: environment)

      {:noreply, socket |> notify(gettext("Seeding queued.")) |> refresh()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  def handle_event("set_library_group", %{"site" => params}, socket) do
    with {:ok, site} <- site_from_socket(socket, params["id"]),
         {:ok, site} <-
           Registry.put_provider_library_group(site, params["provider_library_group"], socket.assigns.current_user) do
      {:noreply,
       socket
       |> drop_draft(:library, site.id)
       |> notify(gettext("Provider library group for %{name} saved.", name: site.name))
       |> refresh()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  def handle_event(event, _params, socket)
      when event in ["grant", "revoke"] and is_map_key(socket.assigns, :authorization) do
    {:noreply, put_flash(socket, :error, gettext("Manage access through this site’s groups."))}
  end

  def handle_event("grant", %{"assignment" => params}, socket) do
    with {:ok, site} <- site_from_socket(socket, params["site_id"]),
         {:ok, user} <- user_from_socket(socket, params["user_id"]),
         {:ok, role} <- parse_role(params["role"]),
         {:ok, _assignment} <- Access.grant(user, site, role) do
      {:noreply, socket |> drop_draft(:grant, site.id) |> notify(gettext("Site access updated.")) |> refresh()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  def handle_event("revoke", params, socket) do
    with {:ok, site} <- site_from_socket(socket, params["site-id"]),
         {:ok, user} <- user_from_socket(socket, params["user-id"]),
         :ok <- Access.revoke(user, site) do
      {:noreply, socket |> notify(gettext("Site access revoked.")) |> refresh()}
    else
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  for {event, operation} <- [
        {"suspend", :suspend_site},
        {"activate_site", :activate_site},
        {"archive", :archive_site},
        {"delete", :delete_site}
      ] do
    def handle_event(unquote(event), %{"id" => id}, socket) do
      with {:ok, site} <- site_from_socket(socket, id),
           {:ok, _site} <- apply(Setup, unquote(operation), [site]) do
        {:noreply, socket |> notify(gettext("Site lifecycle updated.")) |> refresh() |> after_lifecycle(unquote(event))}
      else
        {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:site_usage_measured, scope}, socket) do
    socket = put_overview(socket)
    {:noreply, if(scope in [:all, socket.assigns.selected], do: usage_days(socket, :reload), else: socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp refresh(socket) do
    sites = Registry.list_sites() |> Enum.sort_by(&{&1.name, &1.id})
    {:ok, users} = Brando.Users.list_users(%{order: "asc name"})
    users = Enum.reject(users, &(&1.role == :superuser))

    socket
    |> assign(:sites, sites)
    |> assign(:users, users)
    |> assign(:assignments, Map.new(sites, &{&1.id, Access.list_assignments(&1)}))
    |> assign(:stats, Map.new(sites, &{&1.id, site_stats(&1)}))
    |> assign(:seeding, seeding_by_site(sites))
    |> assign(:superuser?, Boundary.superuser?(socket.assigns.current_user))
    |> assign_new(:drafts, fn -> %{} end)
    |> keep_selection()
    |> usage_days()
  end

  # For a superuser only, read once per mount: the sites' figures, and the
  # free space after the first render. Nil for anyone else, so nothing of it
  # renders; without the table (its migration not run yet) only a sentence.
  defp assign_usage(%{assigns: %{superuser?: true}} = socket) do
    if Usage.table?() do
      media_path = Brando.config(:media_path) |> Path.expand()

      socket
      |> assign(:usage, %{table?: true, media_path: media_path, days: [], days_of: nil})
      |> put_overview()
      |> usage_days()
      |> assign_async(:usage_free, fn -> {:ok, %{usage_free: Measure.free_bytes(media_path)}} end)
    else
      socket |> assign(:usage, %{table?: false}) |> assign(:usage_free, nil)
    end
  end

  defp assign_usage(socket), do: socket |> assign(:usage, nil) |> assign(:usage_free, nil)

  # Again when a measurement lands
  defp put_overview(%{assigns: %{usage: %{table?: true} = usage}} = socket) do
    today = Date.utc_today()
    overview = Usage.overview(today)

    total =
      overview
      |> Map.values()
      |> Enum.map(&(&1.measured && Day.storage_bytes(&1.measured)))
      |> Enum.reject(&is_nil/1)
      |> Enum.sum()

    assign(socket, :usage, Map.merge(usage, %{today: today, overview: overview, total: total}))
  end

  defp put_overview(socket), do: socket

  # The selected site's days: read when another site is selected, or when a
  # measurement of it lands (`:reload`)
  defp usage_days(socket, reload \\ nil)

  defp usage_days(%{assigns: %{usage: %{table?: true, days_of: days_of} = usage, selected: selected}} = socket, reload)
       when days_of != selected or reload == :reload do
    site = Enum.find(socket.assigns.sites, &(&1.id == selected))
    days = if site, do: Usage.days(site, usage.today), else: []
    assign(socket, :usage, %{usage | days: days, days_of: selected})
  end

  defp usage_days(socket, _reload), do: socket

  defp usage_access(%{assigns: %{superuser?: true}}), do: :ok
  defp usage_access(_socket), do: {:error, :forbidden}

  # A site removed meanwhile, here or elsewhere, gives way to the default
  defp keep_selection(%{assigns: %{selected: id, sites: sites}} = socket) when is_integer(id) do
    if Enum.any?(sites, &(&1.id == id)), do: socket, else: assign(socket, :selected, selection(%{}, socket.assigns))
  end

  defp keep_selection(socket), do: socket

  # Per site, each environment and language whose latest seeding is queued,
  # running or failed, or that has no identity in that language: a seeding
  # whose job is gone, or one left out by an application's seeder
  defp seeding_by_site(sites) do
    prefixes = for site <- sites, environment <- site.environments, do: Brando.Tenant.prefix(site, environment)
    jobs = latest_seed_jobs(prefixes)

    Map.new(sites, fn site ->
      environments = Enum.sort_by(site.environments, &{not &1.live, &1.name})
      rows = Enum.flat_map(environments, &seeding_rows(site, &1, jobs))
      busy = rows != [] and SiteLanguageSeed.busy?(site)
      {site.id, Enum.map(rows, &Map.put(&1, :busy, busy))}
    end)
  end

  @finished_states ["completed", "cancelled"]

  defp seeding_rows(site, environment, jobs) do
    prefix = Brando.Tenant.prefix(site, environment)

    case identity_languages(prefix) do
      :unknown ->
        []

      seeded ->
        site.languages
        |> Enum.map(&%{environment: environment, language: &1, job: Map.get(jobs, {prefix, &1})})
        |> Enum.map(fn
          %{job: %Oban.Job{state: state}} = row when state in @finished_states -> %{row | job: nil}
          row -> row
        end)
        |> Enum.filter(&(&1.job || &1.language not in seeded))
    end
  end

  defp latest_seed_jobs([]), do: %{}

  defp latest_seed_jobs(prefixes) do
    worker = inspect(SiteLanguageSeed)

    from(job in Oban.Job,
      where: job.worker == ^worker and fragment("?->>'tenant_prefix'", job.args) in ^prefixes,
      order_by: [asc: job.id]
    )
    |> Repo.all(prefix: "public")
    |> Map.new(&{{&1.args["tenant_prefix"], &1.args["language"]}, &1})
  end

  # Provisioning or a copy would make the job wait (`SiteLanguageSeed`)
  defp ready(site), do: if(SiteLanguageSeed.busy?(site), do: {:error, {:environment_busy, site}}, else: :ok)

  defp identity_languages(prefix) do
    table = Brando.Sites.Identity.__schema__(:source)

    case Ecto.Adapters.SQL.query(Repo.repo(), ~s|SELECT language FROM "#{prefix}"."#{table}"|, []) do
      {:ok, %{rows: rows}} -> List.flatten(rows)
      {:error, _reason} -> :unknown
    end
  end

  defp environment_of(site, id) do
    with {environment_id, ""} <- Integer.parse(to_string(id)),
         %{} = environment <- Enum.find(site.environments, &(&1.id == environment_id)) do
      {:ok, environment}
    else
      _ -> {:error, {:environment_not_found, site}}
    end
  end

  # What saving a site's languages asks of the user (`Setup.update_languages/3`)
  defp authorize_site_update(socket), do: Setup.authorize_settings(socket.assigns.current_user)

  defp put_draft(socket, form, id, draft) do
    case site_from_socket(socket, id) do
      {:ok, site} -> {:noreply, update(socket, :drafts, &Map.put(&1, {form, site.id}, draft))}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  defp drop_draft(socket, form, site_id), do: update(socket, :drafts, &Map.delete(&1, {form, site_id}))

  defp delivery_changed_message(socket, id) do
    name =
      case site_from_socket(socket, id) do
        {:ok, site} -> site.name
        {:error, _reason} -> gettext("The site")
      end

    gettext(
      "%{name}’s delivery changed while the confirmation was open, so nothing was switched. Check what switching does now, and switch again.",
      name: name
    )
  end

  defp site_stats(site) do
    live_environment = Enum.find(site.environments, & &1.live)

    %{
      page_count: page_stat(site, live_environment, :count),
      last_edit: page_stat(site, live_environment, :last_edit)
    }
  end

  defp page_stat(_site, nil, _stat), do: "—"

  defp page_stat(site, environment, stat) do
    prefix = Brando.Tenant.prefix(site, environment)
    table = Brando.Pages.Page.__schema__(:source)

    sql =
      case stat do
        :count -> ~s|SELECT count(*) FROM "#{prefix}"."#{table}"|
        :last_edit -> ~s|SELECT max(updated_at) FROM "#{prefix}"."#{table}"|
      end

    case Ecto.Adapters.SQL.query(Brando.Repo.repo(), sql, []) do
      {:ok, %{rows: [[value]]}} -> value || "—"
      {:error, _reason} -> "—"
    end
  end

  defp site_from_socket(socket, id) do
    with {site_id, ""} <- Integer.parse(to_string(id)),
         %Site{} = site <- Enum.find(socket.assigns.sites, &(&1.id == site_id)) do
      {:ok, site}
    else
      _ -> {:error, :site_not_found}
    end
  end

  defp user_from_socket(socket, id) do
    with {user_id, ""} <- Integer.parse(to_string(id)),
         %User{} = user <- Enum.find(socket.assigns.users, &(&1.id == user_id)) do
      {:ok, user}
    else
      _ -> {:error, :user_not_found}
    end
  end

  # A string list's params (`site[languages][]`, its last row empty), or a
  # site's own list
  defp clean_languages(languages) when is_list(languages) do
    languages
    |> Enum.map(&(&1 |> to_string() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp clean_languages(_languages), do: []

  # The default language select offers the languages in the list; a default
  # no longer in it gives way to the first that is
  defp default_choice(default, languages) do
    if default in languages, do: default, else: List.first(languages)
  end

  defp language_label(code) do
    case Enum.find(Brando.Languages.installation_languages(), &(to_string(&1[:value]) == code)) do
      %{text: text} when is_binary(text) -> "#{text} (#{code})"
      _unknown -> code
    end
  end

  defp default_create_params do
    language = Brando.Languages.installation_default_language()

    %{
      "name" => "",
      "key" => "",
      "languages" => List.wrap(language),
      "default_language" => language,
      "delivery_mode" => "dynamic",
      "demo" => "true"
    }
  end

  defp assign_create_form(socket, params, errors),
    do: assign(socket, :create_form, to_form(params, as: "site", id: "create-site", errors: errors))

  defp changeset_errors({:site_setup_failed, reason, _compensation}), do: changeset_errors(reason)
  defp changeset_errors(%Ecto.Changeset{errors: errors}), do: errors
  defp changeset_errors(_reason), do: []

  defp site_path(%Site{key: key}), do: "/admin/sites?site=#{key}"

  defp after_lifecycle(socket, "delete"), do: push_patch(socket, to: "/admin/sites")
  defp after_lifecycle(socket, _event), do: socket

  defp demo_note(true, Brando.Tenant.Seeder),
    do:
      gettext(
        "Unticked, the homepage and footer start empty and no demo modules are created. The identity, SEO and main menu are created either way."
      )

  defp demo_note(true, seeder),
    do:
      gettext("Unticked, this installation's seeder, %{seeder}, is asked to leave the demo out.", seeder: inspect(seeder))

  defp demo_note(false, seeder),
    do:
      gettext(
        "This installation's seeder, %{seeder}, decides what a new site starts with, so unticking this changes nothing.",
        seeder: inspect(seeder)
      )

  defp delivery_mode_param("static"), do: {:ok, :static}
  defp delivery_mode_param("dynamic"), do: {:ok, :dynamic}
  defp delivery_mode_param(_mode), do: {:error, :invalid_delivery_mode}

  defp other_delivery(:static), do: :dynamic
  defp other_delivery(_dynamic), do: :static

  defp delivery_label(mode) when mode in [:static, "static"], do: gettext("Static")
  defp delivery_label(_dynamic), do: gettext("Dynamic")

  # In a sentence: "Acme now has static delivery."
  defp delivery_name(:static), do: gettext("static")
  defp delivery_name(:dynamic), do: gettext("dynamic")

  defp delivery_description(:static),
    do:
      gettext(
        "Visitors get a generated build: content becomes public when a build is deployed from the site’s Publishing screen."
      )

  defp delivery_description(_dynamic),
    do: gettext("Phoenix answers each request from the live environment, so published content is public at once.")

  defp strategy_label(%DeployConfig{strategy: :local}), do: gettext("Served by this installation")
  defp strategy_label(%DeployConfig{strategy: :rsync, target: target}), do: gettext("rsync to %{target}", target: target)
  defp strategy_label(%DeployConfig{strategy: :s3, target: target}), do: gettext("S3, %{target}", target: target)

  defp strategy_label(%DeployConfig{strategy: :cloudflare_pages, target: target}),
    do: gettext("Cloudflare Pages, %{target}", target: target)

  defp strategy_label(_none), do: gettext("Not set up")

  defp switch_label(:static), do: gettext("Switch to static delivery")
  defp switch_label(:dynamic), do: gettext("Switch to dynamic delivery")

  defp switch_title(site, :static), do: gettext("Switch %{name} to static delivery?", name: site.name)
  defp switch_title(site, :dynamic), do: gettext("Switch %{name} to dynamic delivery?", name: site.name)

  # What the switch changes for visitors, for its confirmation. A static site
  # the installation serves from a published build is the one case where they
  # see it at once: the build is forgotten (`Brando.Sites.Site`), and Phoenix
  # answers the live environment's domain again.
  defp delivery_effect(site, :dynamic) do
    domain = live_domain(site)

    cond do
      LocalDelivery.serving?(site) ->
        gettext(
          "Visitors to %{domain} stop getting published build %{build} and get pages Phoenix renders from the live environment, so content changed since that build becomes public at once. The build is no longer published: switching back to static serves nothing from the installation until the next deploy. Publishing leaves the site’s menu.",
          domain: domain,
          build: site.published_build
        )

      Site.local_delivery?(site) and is_binary(site.published_build) ->
        gettext(
          "Nothing changes for visitors while the site is not active. Once it is active again, Phoenix answers %{domain} instead of published build %{build}, which is no longer published. Publishing leaves the site’s menu.",
          domain: domain,
          build: site.published_build
        )

      Site.local_delivery?(site) ->
        gettext(
          "Nothing changes for visitors: no build is published, so Phoenix already answers %{domain}. Publishing leaves the site’s menu.",
          domain: domain
        )

      true ->
        gettext(
          "Nothing changes for visitors at once: %{domain} keeps reaching whatever its DNS or CDN points at, a static host included, until it is pointed at this installation. Forms on pages deployed to a static host stop accepting submissions, and Publishing leaves the site’s menu.",
          domain: domain
        )
    end
  end

  defp delivery_effect(site, :static) do
    domain = live_domain(site)

    if match?(%DeployConfig{strategy: :local}, site.deploy_config),
      do:
        gettext(
          "Nothing changes for visitors until a build is deployed: Phoenix keeps answering %{domain}, and the installation serves the build from the first deploy. Publishing, where builds are made and deployed, appears in the site’s menu.",
          domain: domain
        ),
      else:
        gettext(
          "Nothing changes for visitors: Phoenix keeps answering %{domain} until it is pointed at the static host a build is deployed to. Publishing, where builds are made and deployed, appears in the site’s menu.",
          domain: domain
        )
  end

  defp live_domain(site) do
    case Enum.find(site.environments || [], & &1.live) do
      %{domain: domain} when is_binary(domain) and domain != "" -> domain
      _none -> gettext("the site’s domain")
    end
  end

  # What activating or restoring the site does for visitors, for its
  # confirmation: its hosts are back in public routing, and a build the
  # installation kept is served again (`Brando.SSG.LocalDelivery`)
  defp activation_effect(site) do
    domain = live_domain(site)

    cond do
      Site.local_delivery?(site) and is_binary(site.published_build) ->
        gettext("Its domains serve again at once: visitors to %{domain} get published build %{build}.",
          domain: domain,
          build: site.published_build
        )

      site.delivery_mode == :static and not Site.local_delivery?(site) ->
        gettext(
          "Its domains are back in public routing at once: Phoenix answers %{domain} again where it points at this installation.",
          domain: domain
        )

      true ->
        gettext("Its domains serve again at once: visitors to %{domain} get the site’s pages from Phoenix.",
          domain: domain
        )
    end
  end

  defp lifecycle_description(%Site{status: :active}),
    do:
      gettext(
        "Suspending takes the site’s domains out of public routing until it is activated again. Archiving does the same, and starts the %{days} days after which it can be permanently deleted.",
        days: Setup.delete_retention_days()
      )

  defp lifecycle_description(%Site{status: :suspended}),
    do: gettext("Suspended: its domains serve nothing until the site is activated again. Nothing is deleted.")

  defp lifecycle_description(%Site{status: :archived}),
    do:
      gettext(
        "Archived: its domains serve nothing. Restore it, or permanently delete it with all its schemas, media and uploaded assets once it has been archived for %{days} days.",
        days: Setup.delete_retention_days()
      )

  defp parse_delivery_mode("static"), do: :static
  defp parse_delivery_mode(_dynamic), do: :dynamic

  defp parse_role("editor"), do: {:ok, :editor}
  defp parse_role("admin"), do: {:ok, :admin}
  defp parse_role(_role), do: {:error, :invalid_role}

  # As the Role select under Grant access names them
  defp role_label(:editor), do: gettext("Editor")
  defp role_label(:admin), do: gettext("Administrator")

  # Who sees this site's provider videos in "Add from …", in the copy under
  # the group field.
  defp library_group_note(_sites, %Site{provider_library_group: nil}),
    do: gettext("Not shared: the video picker offers no provider library on this site.")

  defp library_group_note(sites, %Site{provider_library_group: group} = site) do
    case for(other <- sites, other.id != site.id, other.provider_library_group == group, do: other.name) do
      [] ->
        gettext("No other site is in this group yet.")

      names ->
        gettext("Shares the provider libraries with %{sites}.", sites: Enum.join(names, ", "))
    end
  end

  # What the form shows: the fields as changed since the last save, else the
  # site's own. A change event re-renders the form, and an input that is not
  # focused takes the rendered value, so rendering the saved one would undo
  # what was changed in the other field.
  defp languages_form(drafts, site) do
    draft =
      Map.get_lazy(drafts, {:languages, site.id}, fn ->
        %{languages: site.languages, default_language: site.default_language}
      end)

    to_form(%{"languages" => draft.languages, "default_language" => draft.default_language},
      as: "site",
      id: "languages-site-#{site.id}"
    )
  end

  defp removed_languages(drafts, site) do
    case Map.fetch(drafts, {:languages, site.id}) do
      {:ok, %{languages: languages}} -> site.languages -- clean_languages(languages)
      :error -> []
    end
  end

  defp name_form(drafts, site) do
    to_form(%{"name" => Map.get(drafts, {:name, site.id}, site.name), "key" => site.key},
      as: "site",
      id: "name-site-#{site.id}"
    )
  end

  defp library_form(drafts, site) do
    to_form(%{"provider_library_group" => Map.get(drafts, {:library, site.id}, site.provider_library_group)},
      as: "site",
      id: "library-group-site-#{site.id}"
    )
  end

  defp seeding(seeding, site_id), do: Map.get(seeding, site_id, [])

  # As the string list posts them, blank rows included; the save drops them
  defp deploy_target_rows(params) do
    for field <- ["allowed_rsync_targets", "allowed_s3_targets"], into: %{} do
      {field, params |> Map.get(field) |> List.wrap() |> Enum.map(&to_string/1)}
    end
  end

  # The lists as the form drew them: a blank row after the last entry is the
  # list's add row, one between entries is a row being edited
  defp trailing_trimmed(rows) do
    Map.new(rows, fn {field, entries} ->
      {field, entries |> Enum.reverse() |> Enum.drop_while(&(String.trim(&1) == "")) |> Enum.reverse()}
    end)
  end

  # Only a superuser sees or sets a site's deploy targets: in groups mode,
  # reading this screen takes only the Sites read permission
  defp deploy_targets_access(%{assigns: %{superuser?: true}}), do: :ok
  defp deploy_targets_access(_socket), do: {:error, :forbidden}

  defp seed_again?(%{busy: true}), do: false
  defp seed_again?(%{job: nil}), do: true
  defp seed_again?(%{job: %Oban.Job{state: state}}), do: state in ["discarded", "retryable"]

  defp seeding_status(%{job: nil} = row),
    do:
      gettext("%{environment} has no starting content in %{language}.",
        environment: row.environment.name,
        language: row.language
      )

  defp seeding_status(%{job: %Oban.Job{state: "retryable"} = job} = row),
    do:
      gettext("Seeding %{language} in %{environment} failed, and is retried (attempt %{attempt} of %{max}): %{error}",
        environment: row.environment.name,
        language: row.language,
        attempt: job.attempt,
        max: job.max_attempts,
        error: last_error(job)
      )

  defp seeding_status(%{job: %Oban.Job{state: "discarded"} = job} = row),
    do:
      gettext("Seeding %{language} in %{environment} failed: %{error}",
        environment: row.environment.name,
        language: row.language,
        error: last_error(job)
      )

  defp seeding_status(%{job: %Oban.Job{state: "executing"}} = row),
    do: gettext("Seeding %{language} in %{environment} now…", environment: row.environment.name, language: row.language)

  defp seeding_status(row),
    do:
      gettext("Seeding %{language} in %{environment} is queued.",
        environment: row.environment.name,
        language: row.language
      )

  defp last_error(%Oban.Job{errors: errors}) do
    case Enum.max_by(errors, & &1["attempt"], fn -> nil end) do
      %{"error" => error} -> error |> String.split("\n") |> hd()
      _none -> "—"
    end
  end

  defp status_label(:active), do: pgettext("site status", "Active")
  defp status_label(:suspended), do: pgettext("site status", "Suspended")
  defp status_label(:archived), do: pgettext("site status", "Archived")

  defp status_tone(:active), do: "badge--success"
  defp status_tone(:suspended), do: "badge--attention"
  defp status_tone(:archived), do: nil

  defp assignments(assignments, site_id), do: Map.get(assignments, site_id, [])
  defp stat(stats, site_id, key), do: stats |> Map.get(site_id, %{}) |> Map.get(key, "—")

  @kb 1_024
  @mb 1_024 * @kb
  @gb 1_024 * @mb
  @tb 1_024 * @gb

  defp format_size(bytes) when bytes < @kb, do: "#{bytes} B"
  defp format_size(bytes) when bytes < @mb, do: "#{Float.round(bytes / @kb, 1)} KB"
  defp format_size(bytes) when bytes < @gb, do: "#{Float.round(bytes / @mb, 1)} MB"
  defp format_size(bytes) when bytes < @tb, do: "#{Float.round(bytes / @gb, 1)} GB"
  defp format_size(bytes), do: "#{Float.round(bytes / @tb, 1)} TB"

  defp format_change(bytes) when bytes >= 0, do: "+" <> format_size(bytes)
  defp format_change(bytes), do: "−" <> format_size(-bytes)

  defp format_count(count), do: Brando.Utils.human_spaced_number(count)

  # A UTC day, as the admin writes a date: `12 Oct`, `12. okt.`
  defp format_day(%Date{} = date), do: date |> DateTime.new!(~T[12:00:00]) |> BrandoAdmin.Dates.day()

  defp format_last_edit(%NaiveDateTime{} = datetime), do: BrandoAdmin.Dates.short(datetime)
  defp format_last_edit(%DateTime{} = datetime), do: BrandoAdmin.Dates.short(datetime)
  defp format_last_edit(value), do: value

  # An application's seeder without `seed/4` gives the site its usual
  # content whatever the box says, as `mix brando.setup --no-demo` warns
  defp created_message(site, false, %{demo_option?: false, seeder: seeder}) do
    gettext(
      "Site %{name} created. %{seeder} decides what a new site starts with, so the demo choice was not used.",
      name: site.name,
      seeder: inspect(seeder)
    )
  end

  defp created_message(site, _demo, _assigns), do: gettext("Site %{name} created.", name: site.name)

  defp notify(socket, message) do
    send(self(), {:toast, message})
    socket
  end

  defp notify_error(socket, message) do
    BrandoAdmin.Toast.send_to(socket.assigns.current_user, message, %{level: :error, type: :notification})
    socket
  end

  defp lifecycle_error({:retention_period, days}),
    do: gettext("This site must remain archived for %{days} days before permanent deletion.", days: days)

  defp lifecycle_error(%Ecto.Changeset{} = changeset) do
    BrandoAdmin.Utils.format_changeset_errors(changeset)
  end

  defp lifecycle_error({:site_setup_failed, reason, _compensation}), do: lifecycle_error(reason)

  defp lifecycle_error({:language_not_on_site, site, language}),
    do: gettext("%{language} is not one of %{name}’s languages.", language: language, name: site.name)

  defp lifecycle_error({:environment_not_found, site}),
    do: gettext("That environment is not one of %{name}’s.", name: site.name)

  defp lifecycle_error({:environment_busy, site}),
    do:
      gettext("%{name} is being set up, or one of its environments copied. Seed it again when that has finished.",
        name: site.name
      )

  defp lifecycle_error(:forbidden), do: gettext("You do not have permission for this action.")

  defp lifecycle_error(:deploy_running),
    do: gettext("A deploy of this site is running. Try again when it has finished.")

  defp lifecycle_error(:site_busy),
    do:
      gettext(
        "This site is being set up, archived or changed elsewhere, or its new language is being seeded. Try again in a moment."
      )

  defp lifecycle_error(reason) when is_atom(reason), do: reason |> Atom.to_string() |> String.replace("_", " ")
  defp lifecycle_error(reason), do: inspect(reason)

  defp superuser?(user) do
    if Brando.Authorization.enabled?(),
      do: Brando.Authorization.can?(Brando.Authorization.Scope.installation(user), :read, :sites),
      else: user.role == :superuser
  end
end
