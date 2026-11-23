defmodule BrandoAdmin.IdentifierLinkOpenFormTest do
  # An editor has an article open whose rich text links to a case, and the
  # case's address changes. The rewrite of the stored links tells the open
  # form, as another editor's save does: the form takes the new link where
  # the editor has not changed it, and keeps the editor's own text where
  # they have. Before, the form showed the rows it loaded until a reload.
  #
  # Each save is the browser's, as in TransformerSavesTest: a first
  # `save_form` collects the rows (and blocks), the second, with the token
  # from `b:submit`, writes.
  use Brando.LiveCase, async: true

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.LinkTest.Case
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.Components.Form

  @old_url "https://client.example/work"
  @new_url "/cases/client-work"

  setup %{current_user: me} do
    target =
      Repo.insert!(%Case{
        title: "Client work",
        slug: "client-work",
        type: :external_link,
        external_link: "client.example/work"
      })

    {:ok, identifier} = Brando.Content.create_identifier(Case, target)
    link = linked(identifier, @old_url)

    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Links",
          slug: "links",
          language: "en",
          status: "published",
          quotes: [%{text: link}, %{text: "<p>Plain</p>"}],
          items: [%{label: "A", link: link, sequence: 0}, %{label: "B", link: "<p>Plain</p>", sequence: 1}]
        },
        me
      )

    %{article: article, target: target, identifier: identifier}
  end

  defp linked(identifier, url, text \\ "the work"),
    do: ~s(<p><a href="#{url}" data-identifier-id="#{identifier.id}">#{text}</a></p>)

  # The case's address changes, as its save makes it
  defp move(target) do
    target = target |> Ecto.Changeset.change(type: :full_case) |> Repo.update!()
    {:ok, _identifier} = Brando.Content.update_identifier(Case, target)
  end

  defp open(conn, article, form \\ nil) do
    path = Enum.join(["/admin/articles/update", article.id | List.wrap(form)], "/")
    params = %{"brando_tab" => "a", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
    {view, _} = conn |> put_connect_params(params) |> live_form(path, "article_form")
    await(fn -> form_assigns(view).tab_editing? end)
    view
  end

  defp components(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    components
  end

  defp form_assigns(view), do: Enum.find(components(view), &(&1.module == Form and &1.id == "article_form")).assigns

  defp form_target(view), do: with_target(view, cid_of(view, "#article_form-el"))

  defp await(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("never came true")
      true -> Process.sleep(20) && await(fun, tries - 1)
    end
  end

  # A keystroke as the browser sends it: the whole form, one field changed
  defp type(view, field, value) do
    path = ["article" | List.wrap(field)]
    params = view |> render() |> form_params("#article_form_form") |> put_in(path, value) |> Map.put("_target", path)
    view |> element("#article_form_form") |> render_change(params)
  end

  defp browser_form(view, changes) do
    view
    |> render()
    |> form_params("#article_form_form")
    |> then(&Enum.reduce(changes, &1, fn {path, value}, acc -> put_in(acc, path, value) end))
    |> Plug.Conn.Query.encode()
  end

  # "Save and continue editing", with `changes` in the browser's form
  defp save(view, changes) do
    view |> form_target() |> render_hook("save_form", %{"form" => browser_form(view, changes), "stay" => true})
    assert_push_event(view, "b:submit", %{token: token}, 5_000)
    view |> form_target() |> render_hook("save_form", %{"form" => browser_form(view, changes), "token" => token})
    settle(view)
  end

  defp save_title(view, article, title) do
    save(view, [{["article", "title"], title}])
    await(fn -> Repo.get!(Article, article.id).title == title end)
  end

  # The subtitle links to the case too. The default form draws it as a
  # textarea, whose value `form_params/2` reads escaped, so only `form
  # :notes`, which draws it as rich text, is opened on it.
  defp link_subtitle(article, identifier),
    do: Repo.update_all(from(a in Article, where: a.id == ^article.id), set: [subtitle: linked(identifier, @old_url)])

  defp stored_quotes(article), do: Enum.map(Repo.get!(Article, article.id).quotes, & &1.text)

  defp stored_items(article),
    do: Repo.all(from i in ArticleItem, where: i.article_id == ^article.id, order_by: i.sequence, select: i.link)

  describe "the address changes while the form is open" do
    test "the form shows the new address without a reload", %{conn: conn, article: article} = c do
      view = open(conn, article)

      move(c.target)
      settle(view)

      new = linked(c.identifier, @new_url)
      params = view |> render() |> form_params("#article_form_form")
      assert get_in(params, ["article", "quotes", "0", "text"]) == new
      assert get_in(params, ["article", "items", "0", "link"]) == new
    end
  end

  describe "the editor saves another field" do
    test "a quote and an item keep the new address", %{conn: conn, article: article} = c do
      view = open(conn, article)

      move(c.target)
      # The form hears of the rewrite (its LiveView, then the Form)
      settle(view)
      save_title(view, article, "Saved after the move")

      new = linked(c.identifier, @new_url)
      assert stored_quotes(article) == [new, "<p>Plain</p>"]
      assert stored_items(article) == [new, "<p>Plain</p>"]
    end

    test "a rich-text field keeps the new address", %{conn: conn, article: article} = c do
      link_subtitle(article, c.identifier)
      view = open(conn, article, "notes")

      move(c.target)
      settle(view)
      save_title(view, article, "Saved after the move")

      assert Repo.get!(Article, article.id).subtitle == linked(c.identifier, @new_url)
    end

    test "a transformer's row keeps the new address", %{conn: conn, article: article} = c do
      view = open(conn, article, "transformer_rich_items")

      move(c.target)

      # The form hears of the rewrite and hands the rows to the transformer
      settle(view)
      settle(view)

      save_title(view, article, "Saved after the move")

      assert stored_items(article) == [linked(c.identifier, @new_url), "<p>Plain</p>"]
    end
  end

  describe "the editor changed another row" do
    test "of the items: the linked item keeps the new address", %{conn: conn, article: article} = c do
      view = open(conn, article)

      type(view, ["items", "1", "label"], "Changed")

      move(c.target)
      settle(view)
      save_title(view, article, "Saved after the move")

      assert stored_items(article) == [linked(c.identifier, @new_url), "<p>Plain</p>"]
    end

    # The quotes are one column of the article: the form keeps the row the
    # editor changed and takes the rewritten one
    test "of the quotes: the linked quote keeps the new address", %{conn: conn, article: article} = c do
      view = open(conn, article)

      type(view, ["quotes", "1", "text"], "<p>Changed</p>")

      move(c.target)
      settle(view)
      save_title(view, article, "Saved after the move")

      assert stored_quotes(article) == [linked(c.identifier, @new_url), "<p>Changed</p>"]
    end
  end

  describe "the editor changed the text that holds the link" do
    # The editor's next save decides, as with any edit made beside another
    test "in a quote: their text is saved, and the items keep the new address", %{conn: conn, article: article} = c do
      view = open(conn, article)
      own = linked(c.identifier, @old_url, "the editor's work")

      type(view, ["quotes", "0", "text"], own)

      move(c.target)
      settle(view)
      save_title(view, article, "Saved after the move")

      assert stored_quotes(article) == [own, "<p>Plain</p>"]
      assert stored_items(article) == [linked(c.identifier, @new_url), "<p>Plain</p>"]
    end

    test "in an item: their row is saved", %{conn: conn, article: article} = c do
      view = open(conn, article)
      own = linked(c.identifier, @old_url, "the editor's work")

      type(view, ["items", "0", "link"], own)

      move(c.target)
      settle(view)
      save_title(view, article, "Saved after the move")

      assert stored_items(article) == [own, "<p>Plain</p>"]
      assert stored_quotes(article) == [linked(c.identifier, @new_url), "<p>Plain</p>"]
    end

    test "in the rich-text field: their text is saved", %{conn: conn, article: article} = c do
      link_subtitle(article, c.identifier)
      view = open(conn, article, "notes")
      own = linked(c.identifier, @old_url, "the editor's work")

      type(view, "subtitle", own)

      move(c.target)
      settle(view)
      save_title(view, article, "Saved after the move")

      assert Repo.get!(Article, article.id).subtitle == own
    end
  end
end
