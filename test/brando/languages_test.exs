defmodule Brando.LanguagesTest do
  # A site's own languages and default language on a multi-site installation
  # (`Brando.Languages`). The installation configures Norwegian and English,
  # English its default (config/test.exs). Acme uses English and Norwegian,
  # Norwegian its default; Beta English only.
  use Brando.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Brando.Languages
  alias Brando.Sites.Site
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias BrandoAdmin.Components.ContentLanguageSwitch
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Options

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    acme = site("Acme", "acme", ["en", "no"], "no", "acme.test")
    beta = site("Beta", "beta", ["en"], "en", "beta.test")
    Cache.warm()

    %{acme: acme, beta: beta}
  end

  defp site(name, key, languages, default_language, domain) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: languages,
        default_language: default_language,
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true, domain: domain},
        actor: :system
      )

    Registry.get_site(site.id)
  end

  defp enter(site_key), do: Tenant.put_prefix("tenant_#{site_key}_production")

  describe "the accessors" do
    test "answer for the site the process works for, in its own order, labelled from the installation" do
      enter("acme")
      assert Languages.languages() == [[value: "en", text: "English"], [value: "no", text: "Norsk"]]
      assert Languages.default_language() == "no"

      enter("beta")
      assert Languages.languages() == [[value: "en", text: "English"]]
      assert Languages.default_language() == "en"
    end

    test "answer for the installation outside every site" do
      assert Languages.codes() == ["no", "en"]
      assert Languages.default_language() == "en"
    end

    test "with tenancy off or in single-site mode the installation's list is the site's" do
      enter("beta")

      for mode <- [:none, :single] do
        put_test_env(:tenancy_mode, mode)
        assert Languages.codes() == ["no", "en"], "#{mode}"
        assert Languages.default_language() == "en", "#{mode}"
      end
    end

    test "leave out a language the installation does not configure, and warn when the site is loaded", %{beta: beta} do
      # A row from before the installation dropped German
      {1, _} =
        Brando.Repo.update_all(
          Ecto.Query.from(s in Site, where: s.id == ^beta.id),
          [set: [languages: ["de", "en"], default_language: "de"]],
          prefix: "public"
        )

      log =
        with_log_level(:warning, fn ->
          capture_log(fn -> Cache.warm() end)
        end)

      assert log =~ ~s(Site "beta" lists "de")

      enter("beta")
      assert Languages.codes() == ["en"]
      assert Languages.default_language() == "en"
    end
  end

  describe "admin" do
    test "the content-language switch is offered on a site with two languages and hidden on one with one" do
      enter("acme")
      assert ContentLanguageSwitch.show?()

      enter("beta")
      refute ContentLanguageSwitch.show?()
    end

    test "form choices and the single-language check follow the site" do
      enter("acme")
      assert Enum.map(Options.expand(:languages), & &1.value) == ["en", "no"]
      assert Enum.map(Input.i18n_languages(:content), &elem(&1, 0)) == ["en", "no"]
      refute Brando.I18n.single_language?()

      enter("beta")
      assert Options.expand(:languages) == [%{label: "English", value: "en"}]
      assert Input.i18n_languages(:content) == [{"en", "English"}]
      assert Brando.I18n.single_language?()

      # The admin's own interface languages stay the installation's
      assert length(Options.expand(:admin_languages)) == 2
    end

    test "listing filters follow the site" do
      enter("acme")
      assert BrandoAdmin.Search.languages() == [{"en", "English"}, {"no", "Norsk"}]

      enter("beta")
      assert BrandoAdmin.Search.languages() == [{"en", "English"}]
    end

    test "an editor with content language no who switches to the English-only site works in English", %{conn: conn} do
      user = Brando.Factory.insert(:random_user, role: :superuser, config: %{content_language: "no"})

      conn =
        conn
        |> init_test_session(%{"brando_site_key" => "beta", "brando_environment_key" => "production"})
        |> Plug.Conn.assign(:current_user, user)
        |> Brando.Plug.AdminTenant.call([])

      assert conn.assigns.current_user.config.content_language == "en"
      assert Brando.Repo.get!(Brando.Users.User, user.id).config.content_language == "en"
    end

    test "an editor keeps a content language the site has", %{conn: conn} do
      user = Brando.Factory.insert(:random_user, role: :superuser, config: %{content_language: "en"})

      conn =
        conn
        |> init_test_session(%{"brando_site_key" => "acme", "brando_environment_key" => "production"})
        |> Plug.Conn.assign(:current_user, user)
        |> Brando.Plug.AdminTenant.call([])

      assert conn.assigns.current_user.config.content_language == "en"
    end

    test "the first site's fallbacks use its default language" do
      enter("acme")
      assert Brando.Type.I18nString.get(%{"no" => "Hei", "en" => "Hello"}, "de") == "Hei"

      enter("beta")
      assert Brando.Type.I18nString.get(%{"no" => "Hei", "en" => "Hello"}, "de") == "Hello"
    end
  end

  describe "public side" do
    test "on the English-only site's host /no/… is not a locale; on the other it is" do
      assert locale("beta.test", "/no/prosjekter") == "en"
      assert locale("acme.test", "/no/prosjekter") == "no"
      assert locale("acme.test", "/en/projects") == "en"
    end

    test "the first site's default locale is Norwegian" do
      assert locale("acme.test", "/") == "no"
      assert locale("acme.test", "/projects") == "no"
      assert locale("beta.test", "/") == "en"
    end

    test "the plugs' order does not matter: after Brando.Plug.Tenant the site comes from its assigns" do
      conn =
        :get
        |> Plug.Test.conn("/no/prosjekter")
        |> Map.put(:host, "beta.test")
        |> Brando.Plug.Tenant.call([])
        |> Plug.Test.init_test_session(%{})
        |> Brando.Plug.I18n.put_locale([])

      assert conn.assigns.language == "en"
    end

    test "alternates list each site's own languages" do
      enter("acme")
      assert hreflang_languages() == [:en, :no]

      enter("beta")
      assert hreflang_languages() == [:en]
    end

    test "the sitemap lists each site's own languages" do
      entries = [%{language: :en, uri: "a"}, %{language: :no, uri: "b"}, %{uri: "c"}]

      enter("acme")
      assert entries |> Brando.Sitemap.in_site_languages() |> Enum.map(& &1.uri) == ["a", "b", "c"]

      enter("beta")
      assert entries |> Brando.Sitemap.in_site_languages() |> Enum.map(& &1.uri) == ["a", "c"]
    end
  end

  describe "provisioning" do
    test "refuses a language the installation lacks, and names it" do
      changeset =
        Site.changeset(%{
          name: "Gamma",
          key: "gamma",
          languages: ["en", "de"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      refute changeset.valid?
      {message, _} = changeset.errors[:languages]
      assert message =~ "de"
      assert message =~ "not one of the installation's languages"
    end

    test "refuses a default language outside the site's" do
      changeset =
        Site.changeset(%{
          name: "Gamma",
          key: "gamma",
          languages: ["en"],
          default_language: "no",
          status: :active,
          delivery_mode: :dynamic
        })

      refute changeset.valid?
      assert {"must be included in languages", _} = changeset.errors[:default_language]
    end

    test "editing a site's languages refuses one the installation lacks", %{acme: acme} do
      assert {:error, changeset} = Registry.update_site(acme, %{languages: ["en", "no", "sv"]})
      {message, _} = changeset.errors[:languages]
      assert message =~ "sv"
    end

    test "a row that already holds an unconfigured language still takes other changes", %{beta: beta} do
      {1, _} =
        Brando.Repo.update_all(
          Ecto.Query.from(s in Site, where: s.id == ^beta.id),
          [set: [languages: ["en", "de"]]],
          prefix: "public"
        )

      capture_log(fn ->
        assert {:ok, _} = Registry.update_site(Registry.get_site(beta.id), %{name: "Beta 2"})
      end)
    end

    test "provisioning through the admin's setup is refused too" do
      user = Brando.Factory.insert(:random_user, role: :superuser)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Brando.Tenant.Setup.create_site(
                 %{
                   name: "Gamma",
                   key: "gamma",
                   languages: ["de"],
                   default_language: "de",
                   status: :active,
                   delivery_mode: :dynamic
                 },
                 user
               )

      assert {_message, _} = changeset.errors[:languages]
    end
  end

  defp locale(host, path) do
    conn =
      :get
      |> Plug.Test.conn(path)
      |> Map.put(:host, host)
      |> Plug.Test.init_test_session(%{})
      |> Brando.Plug.I18n.put_locale([])

    conn.assigns.language
  end

  # An English page with a Norwegian alternate
  defp hreflang_languages do
    alternate = %Brando.Pages.Page{id: 2, language: :no, uri: "om", status: :published, has_url: true}
    page = %Brando.Pages.Page{id: 1, language: :en, uri: "about", status: :published, has_url: true}
    page = %{page | alternate_entries: [alternate]}

    conn = Brando.Plug.HTML.put_hreflang(build_conn(), page)
    Enum.map(conn.private.brando_hreflangs, &elem(&1, 0))
  end

  defp with_log_level(level, fun) do
    previous = Logger.level()
    Logger.configure(level: level)

    try do
      fun.()
    after
      Logger.configure(level: previous)
    end
  end
end
