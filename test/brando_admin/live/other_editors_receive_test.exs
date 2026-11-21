defmodule BrandoAdmin.OtherEditorsReceiveTest do
  # What the other editors of an entry receive from a form, through real
  # LiveViews on an article: `notes` draws the subtitle as rich text,
  # `rich_quotes` a quote's text, and the default form draws both as plain
  # text. Synchronous, as EntryFieldSyncTest: both editors' Presence
  # lookups outlive an async test's sandbox.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.SyncTest

  @unsafe ~s{<p><a href="javascript:alert(1)">link</a></p>}

  setup %{current_user: me} do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Andre",
          slug: "andre",
          language: "no",
          status: "published",
          subtitle: "<p>Stored</p>",
          quotes: [%{text: "<p>Første</p>"}, %{text: "<p>Andre</p>"}]
        },
        me
      )

    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    %{article: article, other_conn: log_in_user(Phoenix.ConnTest.build_conn(), other)}
  end

  # `form`: a named form, or nil for the default form
  defp open(conn, article, form) do
    {view, _html} =
      live_form(conn, Enum.join(["/admin/articles/update", article.id | List.wrap(form)], "/"), "article_form")

    view
  end

  defp form_of(view), do: with_target(view, cid_of(view, "#article_form-el"))

  defp params(view), do: view |> render() |> form_params("#article_form_form")

  # A keystroke as the browser sends it: the whole form, one field changed
  defp type(view, field, value) do
    path = ["article" | List.wrap(field)]
    params = view |> params() |> put_in(path, value) |> Map.put("_target", path)
    view |> element("#article_form_form") |> render_change(params)
  end

  # Leaving a field ships what the editor changed
  defp leave(view, name) do
    view |> form_of() |> render_hook("focus", %{"field" => name})
    view |> form_of() |> render_hook("blur", %{"field" => name})
  end

  # "Save and continue editing": two submits, the first collects the
  # blocks, the second writes
  defp save(view) do
    view |> form_of() |> render_hook("save_redirect_target", %{})
    view |> element("#article_form_form") |> render_submit(%{})
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> element("#article_form_form") |> render_submit(%{})
  end

  defp form_source(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BrandoAdmin.Components.Form, _id, assigns, _private, _prints}} -> assigns.form.source
      _ -> nil
    end)
  end

  defp subtitle(view), do: Ecto.Changeset.get_field(form_source(view), :subtitle)

  defp quotes(view) do
    view
    |> params()
    |> get_in(["article", "quotes"])
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} -> row["text"] end)
  end

  # Whatever one editor shipped has reached the other's form: B handles a
  # shipment once A has, and a render of each settles its mailbox
  defp settle_both(a, b), do: Enum.each([a, b, a, b], &settle/1)

  describe "a rich-text value the form's check refuses" do
    test "stays out of the other editor's form until it is corrected", %{conn: conn, article: article} = c do
      a = open(conn, article, "notes")
      b = open(c.other_conn, article, nil)

      type(a, "subtitle", @unsafe)
      assert Brando.RichText.refused?(form_source(a), :subtitle)
      leave(a, "article[subtitle]")
      settle_both(a, b)
      assert subtitle(b) == "<p>Stored</p>"

      type(a, "subtitle", "<p>Fixed</p>")
      leave(a, "article[subtitle]")
      await(fn -> subtitle(b) == "<p>Fixed</p>" end)
    end

    test "in a row stays out of the other editor's rows until it is corrected", %{conn: conn, article: article} = c do
      a = open(conn, article, "rich_quotes")
      b = open(c.other_conn, article, "rich_quotes")

      type(a, ["quotes", "1", "text"], @unsafe)
      leave(a, "article[quotes][1][text]")
      settle_both(a, b)
      assert quotes(b) == ["<p>Første</p>", "<p>Andre</p>"]

      type(a, ["quotes", "1", "text"], "<p>Fixed</p>")
      leave(a, "article[quotes][1][text]")
      await(fn -> quotes(b) == ["<p>Første</p>", "<p>Fixed</p>"] end)
    end

    # Not shipped, it is still this editor's edit. The other editor's form
    # has no subtitle, which its save leaves as stored.
    test "stays in the editor's form when the other editor saves", %{conn: conn, article: article} = c do
      a = open(conn, article, "notes")
      b = open(c.other_conn, article, "rich_quotes")

      type(a, "subtitle", @unsafe)
      leave(a, "article[subtitle]")
      settle_both(a, b)

      type(b, "title", "Lagret")
      save(b)
      await(fn -> Brando.Repo.get!(SyncTest.Article, article.id).title == "Lagret" end)
      await(fn -> Ecto.Changeset.get_field(form_source(a), :title) == "Lagret" end)
      assert subtitle(a) == @unsafe
      assert subtitle(b) == "<p>Stored</p>"
      assert Brando.Repo.get!(SyncTest.Article, article.id).subtitle == "<p>Stored</p>"
    end

    # A recovered form ships what differs from the saved entry, as the
    # oldest edit: not a value the check refuses, which stays this editor's
    # edit, so the other editor's save keeps it. The other editor is on
    # `notes` too, whose save sends the subtitle as the form holds it.
    test "stays out of the other editor's form after a reconnect", %{conn: conn, article: article} = c do
      a = open(conn, article, "notes")
      b = open(c.other_conn, article, "notes")

      type(a, "subtitle", @unsafe)
      recovered = a |> params() |> Map.put("_target", ["image_editor_upload"])
      kill_live(a)

      a = open(conn, article, "notes")
      settle_both(a, b)
      a |> form_of() |> render_hook("recover_form", recovered)
      assert Brando.RichText.refused?(form_source(a), :subtitle)
      settle_both(a, b)
      assert subtitle(b) == "<p>Stored</p>"

      type(b, "title", "Lagret")
      save(b)
      await(fn -> Brando.Repo.get!(SyncTest.Article, article.id).title == "Lagret" end)
      await(fn -> Ecto.Changeset.get_field(form_source(a), :title) == "Lagret" end)
      assert subtitle(a) == @unsafe
      assert Brando.RichText.refused?(form_source(a), :subtitle)
      assert Brando.Repo.get!(SyncTest.Article, article.id).subtitle == "<p>Stored</p>"

      type(a, "subtitle", "<p>Fixed</p>")
      leave(a, "article[subtitle]")
      await(fn -> subtitle(b) == "<p>Fixed</p>" end)
    end
  end

  describe "a rich-text value the form's check rewrites" do
    test "reaches the other editor as stored", %{conn: conn, article: article} = c do
      a = open(conn, article, "notes")
      b = open(c.other_conn, article, nil)

      type(a, "subtitle", "<p>A subtitle</p><!-- note -->")
      leave(a, "article[subtitle]")
      await(fn -> subtitle(b) == "<p>A subtitle</p>" end)
    end
  end

  # The editor follows its hidden input (the TipTap hook's `followInput`),
  # which the server renders with the other editor's value; no
  # `b:tiptap:update` is sent for a field only a named form draws as rich
  # text.
  describe "a rich-text editor only a named form draws" do
    test "has its input rendered with the other editor's change", %{conn: conn, article: article} = c do
      a = open(conn, article, "notes")
      b = open(c.other_conn, article, "notes")

      type(b, "subtitle", "<p>Ny</p>")
      leave(b, "article[subtitle]")
      await(fn -> subtitle(a) == "<p>Ny</p>" end)

      assert a
             |> render()
             |> Floki.parse_document!()
             |> Floki.attribute("#article_subtitle-rich-text input.tiptap-text", "value") ==
               ["<p>Ny</p>"]
    end
  end
end
