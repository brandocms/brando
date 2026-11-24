defmodule BrandoAdmin.LanguageSetLiveTest.SetLive do
  @moduledoc false
  # The content language switch and the alternates drawer of one entry, side
  # by side, for a type that has no form here
  use Phoenix.LiveView

  def mount(_params, %{"user_id" => user_id, "schema" => schema, "id" => id}, socket) do
    schema = String.to_existing_atom(schema)
    entry = Brando.Repo.get!(schema, id)

    {:ok,
     assign(socket,
       current_user: Brando.Repo.get!(Brando.Users.User, user_id),
       entry: entry,
       switch_entry: %{schema: schema, id: entry.id, language: to_string(entry.language)}
     )}
  end

  def render(assigns) do
    ~H"""
    <.live_component
      module={BrandoAdmin.Components.ContentLanguageSwitch}
      id="content-language-switch"
      current_user={@current_user}
      entry={@switch_entry}
    />
    <.live_component
      module={BrandoAdmin.Components.Form.AlternatesDrawer}
      id="alternates-drawer"
      entry={@entry}
      current_user={@current_user}
      on_close={%Phoenix.LiveView.JS{}}
    />
    """
  end
end

defmodule BrandoAdmin.LanguageSetLiveTest do
  # The content language switch offers the versions of an entry's set, and
  # the alternates drawer lists them, the ones linked through another version
  # marked and without Remove (#3942). Articles in three languages
  # (test/support/three_language_articles.exs). Not async: the site's
  # languages are the application's.
  use Brando.LiveCase, async: false
  use Gettext, backend: Brando.Gettext

  import Brando.Test.Users
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Repo
  alias Brando.ThreeLanguageTest.Article
  alias Brando.ThreeLanguageTest.IndependentArticle
  alias Brando.Translations
  alias BrandoAdmin.LanguageSetLiveTest.SetLive

  @options "#content-language-options"
  @linked ".alternates-linked .identifier"

  setup do
    put_test_env(:languages, [
      [value: "no", text: "Norsk"],
      [value: "en", text: "English"],
      [value: "de", text: "Deutsch"]
    ])

    :ok
  end

  defp article(user, language) do
    Repo.insert!(%Article{
      title: "Tittel #{language}",
      slug: "tittel-#{language}",
      language: String.to_existing_atom(language),
      status: :published,
      creator_id: user.id
    })
  end

  defp link(a, b), do: :ok = Article.Alternate.add(a.id, b.id)

  defp owned_by(entry, user),
    do: Repo.update_all(from(e in Article, where: e.id == ^entry.id), set: [creator_id: user.id])

  defp open(conn, user, schema, entry) do
    {:ok, view, _html} =
      live_isolated(conn, SetLive, session: %{"user_id" => user.id, "schema" => to_string(schema), "id" => entry.id})

    view |> element("#content-language-trigger") |> render_click()
    view
  end

  defp option(code), do: "#{@options} button[phx-value-id='#{code}']"
  defp row(entry), do: "#{@linked}[data-id='#{entry.id}']"
  defp drawer(view), do: with_target(view, cid_of(view, "#alternates-drawer"))

  defp linked?(a, b),
    do:
      Repo.aggregate(from(x in Article.Alternate, where: x.entry_id == ^a.id and x.linked_entry_id == ^b.id), :count) > 0

  describe "a synchronized type" do
    setup %{current_user: user} do
      source = article(user, "no")
      {:ok, english} = Translations.create_target(Article, source.id, :en, user)
      german = article(user, "de")
      link(source, german)
      %{source: source, english: english, german: german}
    end

    test "a translation offers the version linked to its source, and the drawer lists it through the source",
         %{conn: conn, current_user: user} = c do
      view = open(conn, user, Article, c.english)

      assert has_element?(view, "#{option("de")}[data-leaves-form]:not([disabled])")
      assert {:error, {:live_redirect, %{to: to}}} = view |> element(option("de")) |> render_click()
      assert to == "/admin/articles/update/#{c.german.id}"

      view = open(conn, user, Article, c.english)
      # Linked to the entry: removable. Through the source: marked, not removable.
      assert has_element?(view, "#{row(c.source)} button[phx-click*=remove_entry]")
      assert has_element?(view, row(c.german))
      refute has_element?(view, "#{row(c.german)} button[phx-click*=remove_entry]")
      assert view |> element(row(c.german)) |> render() =~ "NO"
    end

    test "a forged remove of a version linked through another removes nothing",
         %{conn: conn, current_user: user} = c do
      view = open(conn, user, Article, c.english)

      view |> drawer() |> render_click("remove_entry", %{"id" => c.german.id})
      view |> drawer() |> render_click("remove_entry", %{"id" => -1})
      assert linked?(c.source, c.german)
      assert linked?(c.english, c.source)

      view |> element("#{row(c.source)} button[phx-click*=remove_entry]") |> render_click()
      refute linked?(c.english, c.source)
      assert linked?(c.source, c.german)
    end
  end

  describe "a type that is not synchronized" do
    test "an entry linked to one with a German version offers it, and not to create one",
         %{conn: conn, current_user: user} do
      norsk = article(user, "no")
      english = article(user, "en")
      german = article(user, "de")
      link(norsk, english)
      link(norsk, german)

      view = open(conn, user, IndependentArticle, english)
      assert has_element?(view, "#{option("de")}[data-leaves-form]:not([disabled])")
      refute has_element?(view, "#{@options} [phx-click*=create_translation]")
      refute "de" in Translations.missing_languages(IndependentArticle, Repo.get!(IndependentArticle, english.id))

      assert has_element?(view, row(german))
      refute has_element?(view, "#{row(german)} button[phx-click*=remove_entry]")
    end
  end

  describe "a person who may not read every version" do
    setup %{current_user: user} do
      source = article(user, "no")
      {:ok, english} = Translations.create_target(Article, source.id, :en, user)
      german = article(user, "de")
      link(source, german)

      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      Boundary.put_scope(nil)
      {:ok, _} = Brando.Authorization.Migration.run()

      editor = Brando.ThreeLanguageTest.grant_read(insert_user(permissions: ~w(brando.admin.access)))
      owned_by(english, editor)
      %{editor: editor, source: source, english: english, german: german}
    end

    test "a version linked to the source they may read opens; one they may not is taken, not offered",
         %{conn: conn} = c do
      owned_by(c.german, c.editor)
      view = open(conn, c.editor, Article, c.english)

      assert has_element?(view, "#{option("de")}[data-leaves-form]:not([disabled])")
      assert has_element?(view, "#{option("no")}[disabled]", gettext("No access"))
      refute render(view) =~ "/admin/articles/update/#{c.source.id}"
      refute has_element?(view, row(c.source))
      assert has_element?(view, row(c.german))
    end

    test "a version linked to the source they may not read says so, and nothing of it is shown", %{conn: conn} = c do
      view = open(conn, c.editor, Article, c.english)

      assert has_element?(view, "#{option("de")}[disabled]", gettext("No access"))
      refute render(view) =~ "/admin/articles/update/#{c.german.id}"
      refute has_element?(view, row(c.german))
    end
  end
end
