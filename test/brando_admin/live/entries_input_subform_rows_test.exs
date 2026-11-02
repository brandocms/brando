defmodule BrandoAdmin.EntriesInputSubformRowsTest do
  # An `:entries` input in a subform's rows: it opens whether or not the
  # form's query loaded the rows' identifiers, a pick or "Clear all" changes
  # its row, and in a transformer's rows and a custom subform component's it
  # checks again what the editor may read once permissions change.
  use Brando.LiveCase

  import Brando.Test.Users
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Catalog
  alias Brando.AuthorizationTestResources.Page, as: PolicyPage
  alias Brando.SyncTest
  alias Brando.SyncTest.Article
  alias Brando.SyncTest.ArticleItem

  @form "#article_form_form"
  @linked "Linked page marker"
  @picked "Picked page marker"
  @masked "An entry you can't view"

  setup do
    put_test_env(:tenancy_mode, :none)

    {:ok, article} =
      SyncTest.create_article(%{title: "Rows", slug: "rows", language: "en", status: "draft"}, :system)

    item = Repo.insert!(%ArticleItem{article_id: article.id, label: "Row", sequence: 0})
    join = ArticleItem.__schema__(:association, :related_entries).related
    {linked_page, linked} = page_identifier(@linked)
    Repo.insert!(struct(join, parent_id: item.id, identifier_id: linked.id, sequence: 0))
    {_page, picked} = page_identifier(@picked)

    {:ok, article: article, item: item, join: join, linked: linked, linked_page: linked_page, picked: picked}
  end

  # A page of `Brando.AuthorizationTestResources.Page`, the inputs' only
  # content type, which its owner may read (`Brando.AuthorizationTestPolicy`)
  defp page_identifier(title, creator \\ nil) do
    attrs = [title: title, uri: "#{Brando.Utils.slugify(title)}-#{System.unique_integer([:positive])}"]
    page = Factory.insert(:page, if(creator, do: [{:creator, creator} | attrs], else: attrs))

    identifier =
      Repo.insert!(%Brando.Content.Identifier{schema: PolicyPage, entry_id: page.id, title: title, language: :en})

    {page, identifier}
  end

  defp open(conn, article, form) do
    tab = %{"brando_tab" => "rows", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}

    {view, _} =
      conn |> put_connect_params(tab) |> live_form("/admin/articles/update/#{article.id}/#{form}", "article_form")

    await_editing_tab(view)
    view
  end

  defp await_editing_tab(view, tries \\ 100) do
    cond do
      form_assigns(view).tab_editing? -> :ok
      tries == 0 -> flunk("the tab never came to edit")
      true -> Process.sleep(20) && await_editing_tab(view, tries - 1)
    end
  end

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == BrandoAdmin.Components.Form and &1.id == "article_form")).assigns
  end

  defp params(view), do: view |> render() |> form_params(@form)

  # The identifier ids of the first row's entries, as the form would save them
  defp row_links(view) do
    (get_in(params(view), ["article", "items", "0", "related_entries"]) || %{})
    |> Enum.sort_by(fn {index, _} -> String.to_integer(index) end)
    |> Enum.map(fn {_, row} -> row["identifier_id"] end)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp saved_links(item, join) do
    Repo.all(from l in join, where: l.parent_id == ^item.id, order_by: l.sequence, select: l.identifier_id)
  end

  # "Save and continue editing": the form stays open on the saved entry
  defp stay(view), do: view |> with_target(cid_of(view, "#article_form-el")) |> render_hook("save_redirect_target", %{})

  # The first submit asks the browser for the form (`b:submit`), the second saves
  defp save(view) do
    params = params(view)
    view |> element(@form) |> render_submit(params)
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> element(@form) |> render_submit(params)
  end

  defp saved(item, join, expected, tries \\ 100) do
    case saved_links(item, join) do
      ^expected -> expected
      other when tries == 0 -> other
      _ -> Process.sleep(20) && saved(item, join, expected, tries - 1)
    end
  end

  defp field_text(view, selector) do
    view |> render() |> Floki.parse_document!() |> Floki.find(selector) |> Floki.text()
  end

  # As `Boundary` broadcasts after a write to groups or accounts
  defp permissions_changed(view) do
    send(view.pid, {:authorization_changed, :all})
    render(view)
    render(view)
  end

  defp own(page, user),
    do: Repo.update_all(from(p in Brando.Pages.Page, where: p.id == ^page.id), set: [creator_id: user.id])

  defp superuser(conn), do: conn |> log_in_as() |> elem(0)

  # Reads its own pages through the record read policy, may edit articles
  defp policy_editor(conn) do
    put_test_env(:authorization_mode, :groups)
    keys = for action <- [:read, :update], do: Catalog.get(action, Article).key
    log_in_as(conn, permissions: ["authorization.policy_pages.read" | keys])
  end

  describe "the rows' identifiers" do
    test "need not be loaded by the form's query", %{conn: conn} = c do
      conn = superuser(conn)
      view = open(conn, c.article, "bare_item_entries")

      assert field_text(view, "#article_items_0_related_entries-field-wrapper .identifier-list") =~ @linked
      assert row_links(view) == [to_string(c.linked.id)]
    end

    test "are loaded by the default preloads", %{conn: conn} = c do
      conn = superuser(conn)
      view = open(conn, c.article, "item_entries")

      assert field_text(view, "#article_items_0_related_entries-field-wrapper .identifier-list") =~ @linked
    end

    test "not loaded, are still masked when the editor may not read them", %{conn: conn} = c do
      {conn, _editor} = policy_editor(conn)
      view = open(conn, c.article, "bare_item_entries")
      html = field_text(view, "#article_items_0_related_entries-field-wrapper .identifier-list")

      refute render(view) =~ @linked
      assert html =~ @masked
      assert row_links(view) == [to_string(c.linked.id)]
    end
  end

  describe "in a subform row" do
    setup %{conn: conn} do
      put_test_env(:authorization_mode, :legacy)
      {:ok, conn: superuser(conn)}
    end

    test "a pick goes to the row and is saved with it", %{conn: conn} = c do
      view = open(conn, c.article, "item_entries")
      view |> element("#article_items_0_related_entries-field-wrapper button", "Select entries") |> render_click()

      view
      |> element("#article_items_0_related_entries-entries-options [data-id='#{c.picked.id}']")
      |> render_click()

      assert row_links(view) == [to_string(c.linked.id), to_string(c.picked.id)]
      assert field_text(view, "#article_items_0_related_entries-field-wrapper .identifier-list") =~ @picked

      stay(view)
      save(view)
      assert saved(c.item, c.join, [c.linked.id, c.picked.id]) == [c.linked.id, c.picked.id]
    end

    test "picking a selected entry again removes it from the row", %{conn: conn} = c do
      view = open(conn, c.article, "item_entries")
      view |> element("#article_items_0_related_entries-field-wrapper button", "Select entries") |> render_click()

      view
      |> element("#article_items_0_related_entries-entries-options [data-id='#{c.linked.id}']")
      |> render_click()

      assert row_links(view) == []
    end

    # The row's input is named by its position: once the row above it goes,
    # the picker that stayed open serves another row
    test "a pick from a picker whose row moved is dropped", %{conn: conn} = c do
      other = Repo.insert!(%ArticleItem{article_id: c.article.id, label: "Second", sequence: 1})
      view = open(conn, c.article, "item_entries")
      view |> element("#article_items_0_related_entries-field-wrapper button", "Select entries") |> render_click()

      Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form,
        id: "article_form",
        action: :update_entries,
        field: :items,
        op: {:delete, "id-#{c.item.id}"}
      )

      assert get_in(params(view), ["article", "items", "0", "id"]) == to_string(other.id)

      view
      |> element("#article_items_0_related_entries-entries-options [data-id='#{c.picked.id}']")
      |> render_click()

      assert row_links(view) == []
      assert_push_event(view, "b:alert", %{type: "info"})
    end

    # A saved row reordered into a new row's place looks as a save would to
    # the new row's input: its key goes from new to saved
    test "a pick from a new row's picker is dropped once a saved row takes its place", %{conn: conn} = c do
      view = open(conn, c.article, "item_entries")
      form = BrandoAdmin.Components.Form
      new_row = BrandoAdmin.Components.Form.Input.SubformHelpers.new_row(%ArticleItem{label: "New"})

      Phoenix.LiveView.send_update(view.pid, form,
        id: "article_form",
        action: :update_entries,
        field: :items,
        op: {:append, [new_row]}
      )

      new_key = get_in(params(view), ["article", "items", "1", "_key"])
      assert new_key =~ "new-"

      view |> element("#article_items_1_related_entries-field-wrapper button", "Select entries") |> render_click()

      Phoenix.LiveView.send_update(view.pid, form,
        id: "article_form",
        action: :update_entries,
        field: :items,
        op: {:reorder, [new_key, "id-#{c.item.id}"], false}
      )

      assert get_in(params(view), ["article", "items", "1", "id"]) == to_string(c.item.id)

      view
      |> element("#article_items_1_related_entries-entries-options [data-id='#{c.picked.id}']")
      |> render_click()

      assert get_in(params(view), ["article", "items", "1", "related_entries"])
             |> Map.values()
             |> Enum.map(& &1["identifier_id"]) ==
               [to_string(c.linked.id)]

      assert_push_event(view, "b:alert", %{type: "info"})
    end

    test "\"Clear all\" empties the row and is saved", %{conn: conn} = c do
      view = open(conn, c.article, "item_entries")
      view |> element("#article_items_0_related_entries-field-wrapper button", "Clear all") |> render_click()

      assert row_links(view) == []
      assert params(view)["article"]["title"] == "Rows"

      stay(view)
      save(view)
      assert saved(c.item, c.join, []) == []
    end

    test "a pick leaves the other rows and fields as they are", %{conn: conn} = c do
      other = Repo.insert!(%ArticleItem{article_id: c.article.id, label: "Second", sequence: 1})
      Repo.insert!(struct(c.join, parent_id: other.id, identifier_id: c.linked.id, sequence: 0))
      view = open(conn, c.article, "item_entries")

      view
      |> element(@form)
      |> render_change(
        params(view)
        |> put_in(["article", "items", "1", "label"], "Typed")
        |> Map.put("_target", ["article", "items", "1", "label"])
      )

      view |> element("#article_items_0_related_entries-field-wrapper button", "Clear all") |> render_click()

      params = params(view)
      assert get_in(params, ["article", "items", "1", "label"]) == "Typed"
      assert get_in(params, ["article", "items", "1", "related_entries", "0", "identifier_id"]) == to_string(c.linked.id)
      assert row_links(view) == []
    end
  end

  # `inputs_for :author`, a `has_one`: the subform holds one row, not a list
  describe "in a one-to-one subform" do
    setup %{conn: conn} = c do
      put_test_env(:authorization_mode, :legacy)
      author = Repo.insert!(%Brando.SyncTest.ArticleAuthor{article_id: c.article.id, name: "Author"})
      join = Brando.SyncTest.ArticleAuthor.__schema__(:association, :related_entries).related
      Repo.insert!(struct(join, parent_id: author.id, identifier_id: c.linked.id, sequence: 0))
      {:ok, conn: superuser(conn), author: author, author_join: join}
    end

    defp author_links(view) do
      (get_in(params(view), ["article", "author", "related_entries"]) || %{})
      |> Enum.sort_by(fn {index, _} -> String.to_integer(index) end)
      |> Enum.map(fn {_, row} -> row["identifier_id"] end)
      |> Enum.reject(&(&1 in [nil, ""]))
    end

    test "a pick goes to the row and is saved with it", %{conn: conn} = c do
      view = open(conn, c.article, "author_entries")
      view |> element("#article_author_0_related_entries-field-wrapper button", "Select entries") |> render_click()

      view
      |> element("#article_author_0_related_entries-entries-options [data-id='#{c.picked.id}']")
      |> render_click()

      assert author_links(view) == [to_string(c.linked.id), to_string(c.picked.id)]

      stay(view)
      save(view)
      assert saved(c.author, c.author_join, [c.linked.id, c.picked.id]) == [c.linked.id, c.picked.id]
    end

    # The subform shows a new row for the empty relation; a pick is the first
    # thing to change it
    test "a pick in an empty one makes its row", %{conn: conn} = c do
      Repo.delete!(c.author)
      view = open(conn, c.article, "author_entries")
      view |> element("#article_author_0_related_entries-field-wrapper button", "Select entries") |> render_click()

      view
      |> element("#article_author_0_related_entries-entries-options [data-id='#{c.picked.id}']")
      |> render_click()

      assert author_links(view) == [to_string(c.picked.id)]

      stay(view)
      save(view)
      author = await_author(c.article)
      assert saved(author, c.author_join, [c.picked.id]) == [c.picked.id]
    end

    defp await_author(article, tries \\ 100) do
      case Repo.get_by(Brando.SyncTest.ArticleAuthor, article_id: article.id) do
        nil when tries > 0 -> Process.sleep(20) && await_author(article, tries - 1)
        author -> author
      end
    end

    # A save gives the new row its id, which can't be told from another row
    # moving into its place: the pick is dropped, and the editor told
    test "a picker opened on a new row drops a pick once the row is saved", %{conn: conn} = c do
      Repo.delete!(c.author)
      view = open(conn, c.article, "author_entries")

      view
      |> element(@form)
      |> render_change(
        params(view)
        |> put_in(["article", "author", "name"], "New author")
        |> Map.put("_target", ["article", "author", "name"])
      )

      view |> element("#article_author_0_related_entries-field-wrapper button", "Select entries") |> render_click()

      stay(view)
      save(view)
      author = await_author(c.article)
      assert get_in(params(view), ["article", "author", "id"]) == to_string(author.id)

      view
      |> element("#article_author_0_related_entries-entries-options [data-id='#{c.picked.id}']")
      |> render_click()

      assert author_links(view) == []
      assert_push_event(view, "b:alert", %{type: "info"})
    end

    test "\"Clear all\" empties the row", %{conn: conn} = c do
      view = open(conn, c.article, "author_entries")
      view |> element("#article_author_0_related_entries-field-wrapper button", "Clear all") |> render_click()

      assert author_links(view) == []
      assert get_in(params(view), ["article", "author", "name"]) == "Author"
    end
  end

  # A record read policy decides: the owner reads the page. The rows have no
  # edit to draw them again; a change of permissions must.
  describe "once permissions change" do
    setup %{conn: conn} = c do
      {conn, editor} = policy_editor(conn)
      own(c.linked_page, editor)
      {:ok, conn: conn, editor: editor, other: insert_user()}
    end

    test "a transformer row masks an entry taken from the editor", %{conn: conn} = c do
      view = open(conn, c.article, "transformer_item_entries")
      selector = "#transformer-item-#{c.item.id}_related_entries-field-wrapper .identifier-list"
      assert field_text(view, selector) =~ @linked

      own(c.linked_page, c.other)
      permissions_changed(view)

      refute render(view) =~ @linked
      assert field_text(view, selector) =~ @masked
    end

    test "a custom subform component's row masks an entry taken from the editor", %{conn: conn} = c do
      view = open(conn, c.article, "custom_item_entries")
      selector = "#article_items_0_related_entries-field-wrapper .identifier-list"
      assert field_text(view, selector) =~ @linked

      own(c.linked_page, c.other)
      permissions_changed(view)

      refute render(view) =~ @linked
      assert field_text(view, selector) =~ @masked
    end
  end
end
