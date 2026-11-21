defmodule BrandoAdmin.RichTextFormInUseTest do
  # The admin form checks the rich text of the form it saves from: the
  # article's `notes` form draws its subtitle as rich text, its
  # `rich_quotes` form a quote's text, and the default form draws both as
  # plain text. Through the real form: validate, save and a stored
  # revision. The article has block fields, so every form of it saves
  # through the save with blocks; the save without blocks casts its params
  # the same way (`cast_entry_params/4`).
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]
  import Ecto.Query, only: [from: 2]

  alias Brando.Revisions.Revision
  alias Brando.SyncTest
  alias Brando.SyncTest.Article

  @unsafe [
    ~s{<p><a href="javascript:alert(1)">link</a></p>},
    ~s{<p onclick="alert(1)">text</p>},
    "<p>text</p><script>alert(1)</script>"
  ]
  @commented "<p>A subtitle</p><!-- note -->"
  @sanitized "<p>A subtitle</p>"

  setup %{current_user: me} do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Rik tekst",
          slug: "rik-tekst",
          language: "no",
          status: "published",
          subtitle: "Stored",
          quotes: [%{text: "<p>Stored</p>"}]
        },
        me
      )

    %{article: article}
  end

  defp open(conn, article, form) do
    path = if form, do: "/admin/articles/update/#{article.id}/#{form}", else: "/admin/articles/update/#{article.id}"
    {view, _html} = live_form(conn, path, "article_form")
    view
  end

  defp form_of(view), do: with_target(view, cid_of(view, "#article_form-el"))

  # A keystroke as the browser sends it: the whole form, one field changed
  defp type(view, field, value) do
    path = ["article" | List.wrap(field)]

    params =
      view
      |> render()
      |> form_params("#article_form_form")
      |> put_in(path, value)
      |> Map.put("_target", path)

    view |> element("#article_form_form") |> render_change(params)
  end

  # "Save and continue editing": two submits, the first collects the
  # blocks, the second writes.
  # `params`: what the browser sends, the form as it shows it by default
  defp save(view, params \\ %{}) do
    view |> form_of() |> render_hook("save_redirect_target", %{})
    view |> element("#article_form_form") |> render_submit(params)
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> element("#article_form_form") |> render_submit(params)
    render(view)
  end

  defp other_editor(article, form) do
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    open(log_in_user(Phoenix.ConnTest.build_conn(), other), article, form)
  end

  # Another editor types `html` into the subtitle and leaves the field: the
  # value reaches `view`'s form as a field change, with no cast
  defp other_types_subtitle(other_view, view, html) do
    type(other_view, "subtitle", html)
    other_view |> form_of() |> render_hook("focus", %{"field" => "article[subtitle]"})
    other_view |> form_of() |> render_hook("blur", %{"field" => "article[subtitle]"})
    await(fn -> Ecto.Changeset.get_field(form_source(view), :subtitle) == html end)
  end

  # The revision is stored once the blocks arrive; a refused one shows the
  # form's errors
  defp store_revision(view) do
    view |> form_of() |> render_hook("store_revision", %{})
    assert_push_event(view, "b:scroll_to_first_error", %{}, 5_000)
  end

  defp form_source(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BrandoAdmin.Components.Form, _id, assigns, _private, _prints}} -> assigns.form.source
      _ -> nil
    end)
  end

  defp saved(article), do: Brando.Repo.get!(Article, article.id)

  describe "a top-level rich-text input only a named form declares" do
    test "is refused with unsafe markup on validate and on save", %{conn: conn, article: article} do
      view = open(conn, article, "notes")

      for html <- @unsafe do
        type(view, "subtitle", html)
        assert Keyword.has_key?(form_source(view).errors, :subtitle), html

        save(view)
        assert Keyword.has_key?(form_source(view).errors, :subtitle), html
        assert saved(article).subtitle == "Stored"
      end
    end

    test "is stored sanitized", %{conn: conn, article: article} do
      view = open(conn, article, "notes")
      type(view, "subtitle", @commented)
      save(view)
      await(fn -> saved(article).subtitle == @sanitized end)
    end

    test "is stored as typed from the default form, where it is plain text", %{conn: conn, article: article} do
      view = open(conn, article, nil)
      type(view, "subtitle", @commented)
      save(view)
      await(fn -> saved(article).subtitle == @commented end)
    end

    # The browser still sends the subtitle it showed before the other
    # editor's change: the form keeps the other editor's value over it, and
    # that value is what the save stores, so it is checked
    for {other_form, html} <- [
          {"notes", ~s{<p><a href="javascript:alert(1)">link</a></p>}},
          {nil, ~s{<p onclick="alert(1)">text</p>}}
        ] do
      test "is refused on save when another editor's change on the #{other_form || "default"} form put it there",
           %{conn: conn, article: article} do
        view = open(conn, article, "notes")
        other_view = other_editor(article, unquote(other_form))
        stale = view |> render() |> form_params("#article_form_form")
        assert stale["article"]["subtitle"] == "Stored"

        other_types_subtitle(other_view, view, unquote(html))
        save(view, stale)

        assert Keyword.has_key?(form_source(view).errors, :subtitle)
        assert saved(article).subtitle == "Stored"
      end
    end

    test "is refused in a stored revision", %{conn: conn, article: article} do
      view = open(conn, article, "notes")
      revisions = fn -> Brando.Repo.aggregate(from(r in Revision, where: r.entry_id == ^article.id), :count) end
      before = revisions.()

      type(view, "subtitle", hd(@unsafe))
      store_revision(view)

      assert Keyword.has_key?(form_source(view).errors, :subtitle)
      assert revisions.() == before
    end

    # The default form draws the subtitle as plain text: another editor's
    # value reaches this form as a field change, with no cast
    test "is refused in a stored revision when another editor's change put it there",
         %{conn: conn, article: article} do
      view = open(conn, article, "notes")
      other_view = other_editor(article, nil)
      revisions = fn -> Brando.Repo.aggregate(from(r in Revision, where: r.entry_id == ^article.id), :count) end
      before = revisions.()

      other_types_subtitle(other_view, view, hd(@unsafe))

      store_revision(view)

      assert Keyword.has_key?(form_source(view).errors, :subtitle)
      assert revisions.() == before
    end
  end

  describe "a revision refused for another editor's value" do
    test "is stored once the other editor corrects the value", %{conn: conn, article: article} do
      view = open(conn, article, "notes")
      other_view = other_editor(article, nil)
      revisions = fn -> Brando.Repo.aggregate(from(r in Revision, where: r.entry_id == ^article.id), :count) end
      before = revisions.()

      other_types_subtitle(other_view, view, hd(@unsafe))
      store_revision(view)
      assert revisions.() == before

      other_types_subtitle(other_view, view, "<p>Fine</p>")
      view |> form_of() |> render_hook("store_revision", %{})
      await(fn -> revisions.() == before + 1 end)
    end
  end

  describe "a subform row's rich-text input only a named form declares" do
    test "is refused with unsafe markup on save", %{conn: conn, article: article} do
      view = open(conn, article, "rich_quotes")

      for html <- @unsafe do
        type(view, ["quotes", "0", "text"], html)
        save(view)
        assert [%{errors: [text: _]}] = Ecto.Changeset.get_change(form_source(view), :quotes), html
        assert Enum.map(saved(article).quotes, & &1.text) == ["<p>Stored</p>"]
      end
    end

    test "is stored sanitized", %{conn: conn, article: article} do
      view = open(conn, article, "rich_quotes")
      type(view, ["quotes", "0", "text"], @commented)
      save(view)
      await(fn -> Enum.map(saved(article).quotes, & &1.text) == [@sanitized] end)
    end
  end
end
