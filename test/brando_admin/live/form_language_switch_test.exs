defmodule BrandoAdmin.FormLanguageSwitchTest.SwitchLive do
  @moduledoc false
  # The switch on its own, for an entry of a type that has no form here
  use Phoenix.LiveView

  def mount(_params, %{"user_id" => user_id, "entry" => entry}, socket) do
    {:ok, assign(socket, current_user: Brando.Repo.get!(Brando.Users.User, user_id), entry: entry)}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={BrandoAdmin.Components.ContentLanguageSwitch}
      id="content-language-switch"
      current_user={@current_user}
      entry={@entry}
    />
    """
  end
end

defmodule BrandoAdmin.FormLanguageSwitchTest do
  # In an entry's form, the content language switch is on the entry's
  # language, and a language opens the entry's version in it: one the editor
  # may read, or a new translation on a synchronized type. Elsewhere, and in
  # the form of a type without languages, it sets the preference only.
  # Grouped, one at a time: the groups tests take the authorization lock
  use Brando.LiveCase, async: true, group: :shared_locks

  import Brando.Test.Users
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.Translations
  alias BrandoAdmin.FormLanguageSwitchTest.SwitchLive

  @options "#content-language-options"

  setup %{current_user: user} do
    prefer(user, "en")
    :ok
  end

  defp prefer(user, language),
    do:
      {:ok, _} =
        Brando.Users.update_user(user, %{config: %{content_language: language}}, :system, show_notification: false)

  defp stored(user), do: Repo.get!(Brando.Users.User, user.id).config.content_language

  defp put_groups do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    # The test's superuser keeps creating entries
    {:ok, _} = Brando.Authorization.Migration.run()
    :ok
  end

  defp article(user, language \\ "no") do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Tittel #{language}", slug: "tittel-#{language}", language: language, status: "published", year: 2020},
        user
      )

    article
  end

  defp open_form(conn, path, form_id) do
    {view, _html} = live_form(conn, path, form_id)
    view |> element("#content-language-trigger") |> render_click()
    view
  end

  defp option(code), do: "#{@options} button[phx-value-id='#{code}']"

  # The event as a browser could send it, for a language whatever the list offers
  defp forge(view, code),
    do: view |> with_target(cid_of(view, "#content-language-trigger")) |> render_click("select_language", %{"id" => code})

  defp trash(schema, id),
    do: Repo.update_all(from(e in schema, where: e.id == ^id), set: [deleted_at: DateTime.utc_now(:second)])

  describe "a synchronized type" do
    test "is on the entry's language, and opens its version in the language picked", %{conn: conn, current_user: user} do
      source = article(user)
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)

      view = open_form(conn, "/admin/articles/update/#{source.id}", "article_form")

      # Norwegian, as the entry is: not English, the preference
      assert has_element?(view, "#{option("no")}.current[aria-selected=true]")
      refute has_element?(view, "#{option("en")}.current")
      assert has_element?(view, "#{option("en")}[data-leaves-form]:not([disabled])")

      assert {:error, {:live_redirect, %{to: to}}} = view |> element(option("en")) |> render_click()
      assert to == "/admin/articles/update/#{target.id}"
      assert stored(user) == "en"
    end

    test "a translation is on its own language, and opens the source", %{conn: conn, current_user: user} do
      prefer(user, "no")
      source = article(user)
      {:ok, target} = Translations.create_target(Article, source.id, :en, user)

      view = open_form(conn, "/admin/articles/update/#{target.id}", "article_form")
      assert has_element?(view, "#{option("en")}.current")

      assert {:error, {:live_redirect, %{to: to}}} = view |> element(option("no")) |> render_click()
      assert to == "/admin/articles/update/#{source.id}"
      assert stored(user) == "no"
    end

    test "offers to create the translation of a language without one", %{conn: conn, current_user: user} do
      source = article(user)
      view = open_form(conn, "/admin/articles/update/#{source.id}", "article_form")

      assert has_element?(view, "#{option("en")}[phx-click*=create_translation][data-leaves-form]")
      assert {:error, {:live_redirect, %{to: to}}} = view |> element(option("en")) |> render_click()

      %{entry_id: target_id} = Repo.get_by!(Translations.Member, language: "en", entry_type: to_string(Article))
      assert to == "/admin/articles/update/#{target_id}"
    end

    for mode <- [:legacy, :groups] do
      test "#{mode}: someone who may not create translations is not offered it, and refused",
           %{conn: conn, current_user: user} do
        if unquote(mode) == :groups, do: put_groups()

        {conn, editor} =
          if unquote(mode) == :groups,
            do: log_in_as(conn, permissions: ~w(brando.synctest_articles.read brando.synctest_articles.update)),
            else: log_in_as(conn, role: :user)

        prefer(editor, "no")
        source = article(user)

        view = open_form(conn, "/admin/articles/update/#{source.id}", "article_form")
        assert has_element?(view, "#{option("en")}[disabled]")
        refute has_element?(view, "#{@options} [phx-click*=create_translation]")

        # The create the switch would send, to the form
        assert is_binary(
                 view
                 |> with_target(cid_of(view, "#article_form-el"))
                 |> render_click("create_translation", %{"language" => "en"})
               )

        refute Translations.get_member(Article, source.id)
        assert is_binary(forge(view, "en"))
      end
    end
  end

  describe "a type that is not synchronized" do
    test "opens a linked version, and says a language without one has none", %{conn: conn, current_user: user} do
      norsk = Factory.insert(:page, title: "Norsk side", language: :no, creator: user)
      view = open_form(conn, "/admin/pages/update/#{norsk.id}", "page_form")

      assert has_element?(view, "#{option("no")}.current")
      assert has_element?(view, "#{option("en")}[disabled]")
      refute has_element?(view, "#{@options} [phx-click*=create_translation]")
      assert is_binary(forge(view, "en"))
      assert stored(user) == "en"

      english = Factory.insert(:page, title: "English page", language: :en, creator: user)
      :ok = Page.Alternate.add(norsk.id, english.id)
      prefer(user, "no")

      view = open_form(conn, "/admin/pages/update/#{norsk.id}", "page_form")
      assert {:error, {:live_redirect, %{to: to}}} = view |> element(option("en")) |> render_click()
      assert to == "/admin/pages/update/#{english.id}"
      assert stored(user) == "en"
    end

    test "a language whose version is in the trash says so", %{conn: conn, current_user: user} do
      norsk = Factory.insert(:page, title: "Norsk side", language: :no, creator: user)
      english = Factory.insert(:page, title: "English page", language: :en, creator: user)
      :ok = Page.Alternate.add(norsk.id, english.id)
      trash(Page, english.id)
      prefer(user, "no")

      view = open_form(conn, "/admin/pages/update/#{norsk.id}", "page_form")
      assert has_element?(view, "#{option("en")}[disabled]")
      assert is_binary(forge(view, "en"))
      assert stored(user) == "no"
    end
  end

  test "a type without languages sets the preference only", %{conn: conn, current_user: user} do
    palette = Factory.insert(:palette, creator: user, status: :published)
    view = open_form(conn, "/admin/config/content/palettes/update/#{palette.id}", "palette_form")

    # On the preference, every language offered as before
    assert has_element?(view, "#{option("en")}.current")
    refute has_element?(view, "#{@options} [data-leaves-form]")

    assert is_binary(view |> element(option("no")) |> render_click())
    # The switch's message is handled before this render
    render(view)
    assert stored(user) == "no"
    assert has_element?(view, "#palette_form-el")
  end

  describe "a version the editor may not read" do
    setup do
      put_groups()
    end

    # `Brando.SyncPolicyTest.Article` reads only the entries the person made;
    # its update route is the test articles' form
    test "is not opened, nor sent to by a forged event", %{conn: conn, current_user: user} do
      alias Brando.SyncPolicyTest.Article, as: PolicyArticle

      {conn, editor} = log_in_as(conn, permissions: ~w(authorization.policy_articles.read))
      owner = insert_user()

      {:ok, source} =
        Brando.SyncPolicyTest.create_article(%{title: "Kilde", slug: "kilde", language: "no", status: "published"}, user)

      {:ok, target} = Translations.create_target(PolicyArticle, source.id, :en, user)
      Repo.update_all(from(a in PolicyArticle, where: a.id == ^source.id), set: [creator_id: editor.id])
      Repo.update_all(from(a in PolicyArticle, where: a.id == ^target.id), set: [creator_id: owner.id])
      prefer(editor, "no")

      entry = %{schema: PolicyArticle, id: source.id, language: "no"}

      {:ok, view, _html} = live_isolated(conn, SwitchLive, session: %{"user_id" => editor.id, "entry" => entry})
      view |> element("#content-language-trigger") |> render_click()

      assert has_element?(view, "#{option("en")}[disabled]")
      refute render(view) =~ "/admin/articles/update/#{target.id}"
      assert is_binary(forge(view, "en"))
      assert stored(editor) == "no"

      # Theirs: opened
      Repo.update_all(from(a in PolicyArticle, where: a.id == ^target.id), set: [creator_id: editor.id])
      {:ok, view, _html} = live_isolated(conn, SwitchLive, session: %{"user_id" => editor.id, "entry" => entry})
      view |> element("#content-language-trigger") |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} = view |> element(option("en")) |> render_click()
      assert to == "/admin/articles/update/#{target.id}"
    end
  end
end
