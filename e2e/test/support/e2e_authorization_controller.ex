defmodule E2EAuthorizationController do
  @moduledoc false
  use E2eProjectWeb, :controller
  import Ecto.Query, only: [from: 2]
  alias Brando.Authorization.{Catalog, Groups, Migration, Scope}
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Registry}
  alias E2eProject.Repo

  def run(conn, params) do
    [beam | _] = Plug.Conn.get_req_header(conn, "user-agent")
    Phoenix.Ecto.SQL.Sandbox.allow(beam, Ecto.Adapters.SQL.Sandbox)
    perform(conn, params)
  end

  defp perform(conn, %{"action" => "setup"}) do
    Tenant.Cache.clear()
    owner = Repo.get_by!(Brando.Users.User, email: "admin@brandocms.com")
    editor = Repo.get_by!(Brando.Users.User, email: "editor@brandocms.com")
    alpha = site("Alpha", "auth-alpha")
    beta = site("Beta", "auth-beta")
    production = environment(alpha, "production", "Production", true)
    staging = environment(alpha, "staging", "Staging", false)
    beta_live = environment(beta, "production", "Production", true)
    {:ok, _} = Migration.run()
    {:ok, installation} = Groups.list(Scope.installation(owner))
    for group <- installation, do: Groups.remove_member(Scope.installation(owner), group.id, editor.id)
    # The seed account's installation import is retry-safe after removal.
    {:ok, _} = Access.grant(editor, alpha, :admin)
    {:ok, _} = Access.grant(editor, beta, :editor)

    {:ok, alpha_group} =
      Groups.create(Scope.site(owner, alpha), %{name: "Alpha managers"}, Catalog.preset_permissions(:admin, :site))

    {:ok, :ok} = Groups.add_member(Scope.site(owner, alpha), alpha_group.id, editor.id)

    outsider =
      Repo.insert!(%Brando.Users.User{
        name: "Beta colleague",
        email: "beta-only@brandocms.com",
        role: :user,
        language: :en,
        avatar: nil,
        config: %Brando.Users.UserConfig{}
      })

    {:ok, _} = Access.grant(outsider, beta, :editor)

    if Tenant.mode() == :multi do
      {:ok, beta_group} =
        Groups.create(
          Scope.site(owner, beta),
          %{name: "Beta readers"},
          ~w(brando.admin.access brando.pages.read brando.profile.read brando.profile.update)
        )

      {:ok, :ok} = Groups.add_member(Scope.site(owner, beta), beta_group.id, editor.id)
      {:ok, :ok} = Groups.add_member(Scope.site(owner, beta), beta_group.id, outsider.id)
    end

    for {site, environment, title} <- [
          {alpha, production, "Alpha production page"},
          {alpha, staging, "Alpha staging page"},
          {beta, beta_live, "Beta production page"}
        ] do
      Repo.update_all(from(p in Brando.Pages.Page, where: p.id == 1), [set: [title: title, status: :draft]],
        prefix: Tenant.prefix(site, environment)
      )
    end

    json(conn, %{alpha_group_id: alpha_group.id, editor_id: editor.id, outsider_id: outsider.id})
  end

  defp perform(conn, %{"action" => "titles"}) do
    titles =
      for {site_key, env_key} <- [{"auth-alpha", "production"}, {"auth-alpha", "staging"}, {"auth-beta", "production"}],
          into: %{} do
        site = Registry.get_site_by_key(site_key)
        environment = Registry.get_environment_by_key(site, env_key)
        page = Repo.get!(Brando.Pages.Page, 1, prefix: Tenant.prefix(site, environment))
        {"#{site_key}/#{env_key}", %{title: page.title, status: page.status}}
      end

    json(conn, titles)
  end

  defp perform(conn, %{"action" => "revoke", "group_id" => group_id}) do
    owner = Repo.get_by!(Brando.Users.User, email: "admin@brandocms.com")
    editor = Repo.get_by!(Brando.Users.User, email: "editor@brandocms.com")
    alpha = Registry.get_site_by_key("auth-alpha")
    {:ok, :ok} = Groups.remove_member(Scope.site(owner, alpha), group_id, editor.id)
    json(conn, %{ok: true})
  end

  defp site(name, key) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    site
  end

  defp environment(site, key, name, live) do
    {:ok, environment} = Registry.create_environment(site, %{name: name, key: key, live: live})
    prefix = Tenant.prefix(site, environment)
    Ecto.Adapters.SQL.query!(Repo, ~s(CREATE SCHEMA "#{prefix}"))
    %{rows: rows} = Ecto.Adapters.SQL.query!(Repo, "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")

    rows
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")
      Ecto.Adapters.SQL.query!(Repo, ~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
      Ecto.Adapters.SQL.query!(Repo, ~s(INSERT INTO "#{prefix}"."#{escaped}" SELECT * FROM public."#{escaped}"))
    end)

    environment
  end
end
