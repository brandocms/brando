defmodule Brando.Content.Proposals.TranslationWorkSitesTest do
  # `translation_work` reads a translation only in a site where the person
  # may read it (#3744). Not async: each test creates two sites' schemas.
  use Brando.ConnCase, async: false

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Proposals.Tools
  alias Brando.Content.Proposals.Tools.Context
  alias Brando.Factory
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Tenant
  alias Brando.Translations
  alias Ecto.Adapters.SQL

  setup do
    Boundary.put_scope(nil)
    on_exit(fn -> Boundary.put_scope(nil) end)
    author = Factory.insert(:random_user, role: :superuser)

    # Copied into both sites' schemas below
    {:ok, source} =
      SyncTest.create_article(%{title: "Tittel", slug: "tittel", language: "no", status: "published"}, author)

    {:ok, target} = Translations.create_target(Article, source.id, :en, author)

    # Content first, as legacy authorization allows; then groups decide
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    alpha = site("Work Alpha", "work-alpha")
    beta = site("Work Beta", "work-beta")
    alpha_live = environment(alpha, "production")
    beta_live = environment(beta, "production")

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    %{alpha: alpha, alpha_live: alpha_live, beta: beta, beta_live: beta_live, target: target}
  end

  defp site(name, key) do
    {:ok, site} =
      Tenant.Registry.create_site(%{
        name: name,
        key: key,
        languages: ["no", "en"],
        default_language: "no",
        status: :active,
        delivery_mode: :dynamic
      })

    site
  end

  defp environment(site, key) do
    {:ok, environment} = Tenant.Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
    prefix = Tenant.prefix(site, environment)
    repo = Brando.RuntimeConfig.get(:repo_module)
    SQL.query!(repo, ~s(CREATE SCHEMA "#{prefix}"))
    tables = SQL.query!(repo, "SELECT tablename FROM pg_tables WHERE schemaname = 'public'").rows

    tables
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      SQL.query!(repo, ~s|CREATE TABLE "#{prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|)
      SQL.query!(repo, ~s(INSERT INTO "#{prefix}"."#{table}" SELECT * FROM public."#{table}"))
    end)

    environment
  end

  defp in_scope(scope, fun), do: Tenant.with_prefix(scope.prefix, fn -> Boundary.with_scope(scope, fun) end)

  test "a reader in one site does not reach the same entry in another", c do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    owner = Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Migration.run()
    owner_scope = Scope.site(owner, c.alpha, c.alpha_live)

    {:ok, group} =
      Groups.create(owner_scope, %{name: "Alpha readers #{System.unique_integer([:positive])}"}, [
        "brando.admin.access",
        "brando.assistant.use",
        "brando.synctest_articles.read"
      ])

    {:ok, :ok} = Groups.add_member(owner_scope, group.id, user.id)
    args = %{"content_type" => "Brando.SyncTest.Article", "id" => c.target.id}

    in_scope(Scope.site(user, c.alpha, c.alpha_live), fn ->
      assert {:ok, %{units: [%{key: "title"}]}} = Tools.call("translation_work", args, %Context{actor: user})
    end)

    in_scope(Scope.site(user, c.beta, c.beta_live), fn ->
      assert {:error, message} = Tools.call("translation_work", args, %Context{actor: user})
      refute message =~ "Tittel"
    end)
  end
end
