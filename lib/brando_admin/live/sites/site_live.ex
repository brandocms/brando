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
     events: ~w(create_site activate_site delete suspend archive grant revoke set_library_group save_languages)}
  )

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup
  alias Brando.Tenant.Storage
  alias Brando.Users.User
  alias Brando.Worker.SiteLanguageSeed
  alias BrandoAdmin.Components.Content

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    cond do
      Brando.Tenant.mode() != :multi or not superuser?(socket.assigns.current_user) ->
        {:ok, redirect(socket, to: "/admin")}

      connected?(socket) ->
        {:ok, socket |> assign(:socket_connected, true) |> refresh()}

      true ->
        {:ok, assign(socket, :socket_connected, false)}
    end
  end

  @impl Phoenix.LiveView
  def render(%{socket_connected: false} = assigns) do
    ~H"""
    """
  end

  def render(assigns) do
    ~H"""
    <div class="environment-screen site-screen">
      <Content.header
        title={gettext("Sites")}
        subtitle={gettext("Provision isolated sites, control lifecycle, and assign users")}
      >
        <button type="button" class="btn" phx-click="refresh">{gettext("Refresh")}</button>
      </Content.header>

      <div class="environment-management-live">
        <section class="environment-panel">
          <h2>{gettext("Create site")}</h2>
          <p>{gettext("Creates Production and Staging schemas, seeds initial content, and grants you site admin access.")}</p>
          <form id="create-site-form" phx-submit="create_site">
            <div class="environment-grid">
              <label>
                <span>{gettext("Name")}</span>
                <input name="site[name]" required placeholder={gettext("Acme Corporation")} />
              </label>
              <label>
                <span>{gettext("Key")}</span>
                <input name="site[key]" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" placeholder="acme" />
              </label>
              <label>
                <span>{gettext("Languages")}</span>
                <input
                  name="site[languages]"
                  required
                  value={Brando.Languages.installation_default_language()}
                  placeholder={Enum.join(Brando.Languages.installation_codes(), ",")}
                />
              </label>
              <label>
                <span>{gettext("Default language")}</span>
                <input name="site[default_language]" required value={Brando.Languages.installation_default_language()} />
              </label>
              <label>
                <span>{gettext("Delivery")}</span>
                <select name="site[delivery_mode]">
                  <option value="dynamic">{gettext("Dynamic")}</option>
                  <option value="static">{gettext("Static")}</option>
                </select>
                <small>
                  {gettext(
                    "Dynamic is served directly by Phoenix. Static requires a configured SSG build and deploy pipeline."
                  )}
                </small>
              </label>
            </div>
            <button type="submit" class="btn btn--primary" phx-disable-with={gettext("Provisioning…")}>
              {gettext("Create site")}
            </button>
          </form>
        </section>

        <section :for={site <- @sites} class="environment-panel site-card" id={"site-#{site.id}"}>
          <header class="site-card__header">
            <div class="site-card__identity">
              <h2>{site.name}</h2>
              <code class="badge badge--outline">{site.key}</code>
              <span class={["badge", status_tone(site.status)]}>
                <span :if={site.status == :active} class="badge-dot"></span>
                {status_label(site.status)}
              </span>
            </div>
            <div class="site-card__actions">
              <button
                :if={site.status == :active}
                type="button"
                class="btn"
                phx-click="suspend"
                phx-value-id={site.id}
              >
                {gettext("Suspend")}
              </button>
              <button
                :if={site.status == :suspended}
                type="button"
                class="btn btn--primary"
                phx-click="activate_site"
                phx-value-id={site.id}
              >
                {gettext("Activate")}
              </button>
              <button
                :if={site.status != :archived}
                type="button"
                class="btn btn--danger"
                phx-click="archive"
                phx-value-id={site.id}
                phx-confirm={gettext("Archive %{name}? Its domains will stop serving immediately.", name: site.name)}
              >
                {gettext("Archive")}
              </button>
              <button
                :if={site.status == :archived}
                type="button"
                class="btn"
                phx-click="activate_site"
                phx-value-id={site.id}
              >
                {gettext("Restore")}
              </button>
              <button
                :if={site.status == :archived}
                type="button"
                class="btn btn--danger"
                phx-click="delete"
                phx-value-id={site.id}
                phx-confirm={gettext("Permanently delete %{name}, all schemas, media, and uploaded assets?", name: site.name)}
              >
                {gettext("Permanently delete")}
              </button>
            </div>
          </header>

          <dl class="site-stats">
            <div>
              <dt>{gettext("Environments")}</dt><dd>{length(site.environments)}</dd>
            </div>
            <div>
              <dt>{gettext("Pages")}</dt><dd>{stat(@stats, site.id, :page_count)}</dd>
            </div>
            <div>
              <dt>{gettext("Media")}</dt><dd>{format_size(stat(@stats, site.id, :media_size))}</dd>
            </div>
            <div>
              <dt>{gettext("Last page edit")}</dt><dd>{format_last_edit(stat(@stats, site.id, :last_edit))}</dd>
            </div>
          </dl>

          <form
            id={"languages-site-#{site.id}"}
            class="site-languages"
            phx-change="check_languages"
            phx-submit="save_languages"
          >
            <input type="hidden" name="site[id]" value={site.id} />
            <div class="environment-grid">
              <label>
                <span>{gettext("Languages")}</span>
                <input
                  name="site[languages]"
                  required
                  value={language_draft(@language_drafts, site).languages}
                  placeholder={Enum.join(Brando.Languages.installation_codes(), ",")}
                />
                <small>
                  {gettext("A language you add gets the same starting content as a new site, in each environment.")}
                </small>
              </label>
              <label>
                <span>{gettext("Default language")}</span>
                <input
                  name="site[default_language]"
                  required
                  value={language_draft(@language_drafts, site).default_language}
                />
              </label>
            </div>
            <p :if={removed_languages(@language_drafts, site) != []} class="environment-hint" role="status">
              {gettext(
                "Removing %{languages} deletes nothing: the content stays, and comes back if the language is added again.",
                languages: Enum.join(removed_languages(@language_drafts, site), ", ")
              )}
            </p>
            <button type="submit" class="btn">{gettext("Save languages")}</button>
          </form>

          <div :if={seeding(@seeding, site.id) != []} class="site-seeding">
            <table id={"seeding-site-#{site.id}"}>
              <tbody>
                <tr :for={row <- seeding(@seeding, site.id)} id={"seeding-#{site.id}-#{row.environment.id}-#{row.language}"}>
                  <td>{seeding_status(row)}</td>
                  <td>
                    <small :if={row.busy}>{gettext("Waiting for the environment's copy or setup to finish.")}</small>
                    <button
                      :if={seed_again?(row)}
                      type="button"
                      class="btn btn--sm"
                      phx-click="seed_language"
                      phx-value-site-id={site.id}
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

          <form
            id={"library-group-site-#{site.id}"}
            class="site-library-group"
            phx-submit="set_library_group"
          >
            <input type="hidden" name="site[id]" value={site.id} />
            <label>
              <span>{gettext("Provider library group")}</span>
              <input
                name="site[provider_library_group]"
                value={site.provider_library_group}
                pattern="[a-z0-9]+(?:-[a-z0-9]+)*"
                maxlength="40"
                placeholder={gettext("Not shared")}
              />
              <small>{library_group_note(@sites, site)}</small>
            </label>
            <button type="submit" class="btn">{gettext("Save group")}</button>
          </form>

          <p :if={Brando.Authorization.enabled?()}>
            <a href={"/admin/groups?brando_site_key=#{site.key}"}>{gettext("Manage this site’s groups and members →")}</a>
          </p>
          <div :if={!Brando.Authorization.enabled?()} class="environment-grid site-card__users">
            <section>
              <h3>{gettext("Site users")}</h3>
              <p :if={assignments(@assignments, site.id) == []}>{gettext("No explicit user assignments.")}</p>
              <table :if={assignments(@assignments, site.id) != []}>
                <tbody>
                  <tr :for={assignment <- assignments(@assignments, site.id)} id={"assignment-#{assignment.id}"}>
                    <td>{assignment.user.name}<small>{assignment.user.email}</small></td>
                    <td><span class="badge">{role_label(assignment.role)}</span></td>
                    <td>
                      <button
                        type="button"
                        class="btn btn--sm btn--danger"
                        phx-click="revoke"
                        phx-value-site-id={site.id}
                        phx-value-user-id={assignment.user_id}
                      >
                        {gettext("Revoke")}
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </section>

            <section>
              <h3>{gettext("Grant access")}</h3>
              <p :if={@users == []}>
                {gettext(
                  "Every user here is a superuser, who already has access to every site. Access is granted to users with another role."
                )}
              </p>
              <form :if={@users != []} phx-submit="grant" id={"grant-site-#{site.id}"}>
                <input type="hidden" name="assignment[site_id]" value={site.id} />
                <label>
                  <span>{gettext("User")}</span>
                  <select name="assignment[user_id]" required>
                    <option :for={user <- @users} value={user.id}>{user.name} · {user.email}</option>
                  </select>
                </label>
                <label>
                  <span>{gettext("Role")}</span>
                  <select name="assignment[role]">
                    <option value="editor">{gettext("Editor")}</option>
                    <option value="admin">{gettext("Administrator")}</option>
                  </select>
                </label>
                <button type="submit" class="btn btn--primary">{gettext("Grant access")}</button>
              </form>
            </section>
          </div>
        </section>
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveView
  def handle_event("refresh", _params, socket), do: {:noreply, refresh(socket)}

  def handle_event("create_site", %{"site" => params}, socket) do
    attrs = %{
      name: params["name"],
      key: params["key"],
      languages: parse_languages(params["languages"]),
      default_language: params["default_language"],
      status: :active,
      delivery_mode: parse_delivery_mode(params["delivery_mode"])
    }

    case Setup.create_site(attrs, socket.assigns.current_user) do
      {:ok, site} -> {:noreply, socket |> notify(gettext("Site %{name} created.", name: site.name)) |> refresh()}
      {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
    end
  end

  def handle_event("check_languages", %{"site" => params}, socket) do
    case site_from_socket(socket, params["id"]) do
      {:ok, site} ->
        draft = %{languages: params["languages"] || "", default_language: params["default_language"] || ""}
        {:noreply, update(socket, :language_drafts, &Map.put(&1, site.id, draft))}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("save_languages", %{"site" => params}, socket) do
    attrs = %{languages: parse_languages(params["languages"]), default_language: params["default_language"]}

    with {:ok, site} <- site_from_socket(socket, params["id"]),
         {:ok, site} <- Setup.update_languages(site, attrs, socket.assigns.current_user) do
      {:noreply,
       socket
       |> update(:language_drafts, &Map.delete(&1, site.id))
       |> notify(gettext("Languages for %{name} saved.", name: site.name))
       |> refresh()}
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
      {:noreply, socket |> notify(gettext("Site access updated.")) |> refresh()}
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
        {:noreply, socket |> notify(gettext("Site lifecycle updated.")) |> refresh()}
      else
        {:error, reason} -> {:noreply, notify_error(socket, lifecycle_error(reason))}
      end
    end
  end

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
    |> assign_new(:language_drafts, fn -> %{} end)
  end

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
  defp authorize_site_update(socket) do
    socket.assigns.current_user
    |> Brando.Authorization.Scope.installation()
    |> Brando.Authorization.Boundary.authorize(:update, :sites)
  end

  defp site_stats(site) do
    live_environment = Enum.find(site.environments, & &1.live)

    %{
      page_count: page_stat(site, live_environment, :count),
      last_edit: page_stat(site, live_environment, :last_edit),
      media_size: directory_size(Storage.media_root(site))
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

  defp directory_size(path) do
    case File.ls(path) do
      {:ok, entries} ->
        Enum.reduce(entries, 0, fn entry, total -> total + entry_size(path, entry) end)

      {:error, _reason} ->
        0
    end
  end

  defp entry_size(path, entry) do
    child = Path.join(path, entry)

    case File.lstat(child) do
      {:ok, %{type: :regular, size: size}} -> size
      {:ok, %{type: :directory}} -> directory_size(child)
      _symlink_or_error -> 0
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

  defp parse_languages(languages) do
    languages
    |> to_string()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

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

  # What the form shows: the fields as typed since the last save, else the
  # site's own. A change event re-renders the card, and an input that is not
  # focused takes the rendered value, so rendering the saved one would undo
  # what was typed in the other field.
  defp language_draft(drafts, site) do
    Map.get_lazy(drafts, site.id, fn ->
      %{languages: Enum.join(site.languages, ","), default_language: site.default_language}
    end)
  end

  defp removed_languages(drafts, site) do
    case Map.fetch(drafts, site.id) do
      {:ok, %{languages: languages}} -> site.languages -- parse_languages(languages)
      :error -> []
    end
  end

  defp seeding(seeding, site_id), do: Map.get(seeding, site_id, [])

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

  defp format_size("—"), do: "—"
  defp format_size(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_last_edit(%NaiveDateTime{} = datetime), do: BrandoAdmin.Dates.short(datetime)
  defp format_last_edit(%DateTime{} = datetime), do: BrandoAdmin.Dates.short(datetime)
  defp format_last_edit(value), do: value

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

  defp lifecycle_error(reason) when is_atom(reason), do: reason |> Atom.to_string() |> String.replace("_", " ")
  defp lifecycle_error(reason), do: inspect(reason)

  defp superuser?(user) do
    if Brando.Authorization.enabled?(),
      do: Brando.Authorization.can?(Brando.Authorization.Scope.installation(user), :read, :sites),
      else: user.role == :superuser
  end
end
