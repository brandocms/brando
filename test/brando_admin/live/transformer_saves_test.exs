defmodule BrandoAdmin.TransformerSavesTest do
  # Saves that stay on the form, through the real form, of an entry with a
  # transformer subform: with blocks (an article's `transformer_rich_items`
  # form) and without (an album). Each save is the browser's: a first
  # `save_form` collects the rows (and blocks), the server answers with
  # `b:submit` and its token, and a second `save_form` with that token
  # writes. The rows are edited as the Transformer's hooks edit them.
  use Brando.LiveCase, async: true

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Transformer

  @unsafe ~s{<p onclick="alert(1)">Row</p>}

  setup %{current_user: me} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Rows", slug: "rows", language: "en", status: "published", items: [%{label: "A", sequence: 0}]},
        me
      )

    [stored] = Repo.preload(article, :items).items
    %{article: article, stored: stored}
  end

  @forms %{
    "with blocks" => {"/admin/articles/update/:id/transformer_rich_items", "article_form", "article"},
    "without blocks" => {"/admin/albums/update/:id", "album_form", "album"}
  }

  defp open(conn, article, kind) do
    {path, id, singular} = Map.fetch!(@forms, kind)
    tab = %{"brando_tab" => "rows", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}

    {view, _} =
      conn |> put_connect_params(tab) |> live_form(String.replace(path, ":id", to_string(article.id)), id)

    await(fn -> form_assigns(view, id).tab_editing? end)
    %{view: view, id: id, singular: singular}
  end

  defp components(%{view: view}) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    components
  end

  defp form_assigns(view, id) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == id)).assigns
  end

  defp transformer(form), do: Enum.find(components(form), &(&1.module == Transformer)).assigns

  defp form_target(%{view: view, id: id}), do: with_target(view, cid_of(view, "##{id}-el"))

  defp transformer_target(%{view: view} = form),
    do: with_target(view, cid_of(view, "##{transformer(form).id}-uploader"))

  defp await(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("never came true")
      true -> Process.sleep(20) && await(fun, tries - 1)
    end
  end

  # A row added with `label`
  defp add_row(form, label) do
    before = Enum.map(transformer(form).items, & &1.dom_id)
    form |> transformer_target() |> render_hook("add_entry", %{})
    [dom_id] = Enum.map(transformer(form).items, & &1.dom_id) -- before
    set_field(form, dom_id, "label", label)
    dom_id
  end

  defp set_field(form, dom_id, field, value) do
    form |> transformer_target() |> render_hook("update_field", %{"dom_id" => dom_id, "field" => field, "value" => value})
  end

  defp dom_id_of(form, label) do
    Enum.find_value(transformer(form).items, fn item ->
      if Map.merge(Map.new(Map.take(item.source, [:label])), item.changes)[:label] == label, do: item.dom_id
    end)
  end

  defp browser_form(%{view: view, id: id}, changes) do
    view
    |> render()
    |> form_params("##{id}_form")
    |> then(&Enum.reduce(changes, &1, fn {path, value}, acc -> put_in(acc, path, value) end))
    |> Plug.Conn.Query.encode()
  end

  # "Save and continue editing" as the browser makes it: the first push
  # collects, the second answers `b:submit` with its token
  defp save(form, changes \\ []) do
    form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form, changes), "stay" => true})
    assert_push_event(form.view, "b:submit", %{token: token}, 5_000)
    form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form, changes), "token" => token})
    settle(form.view)
    token
  end

  defp rows(article) do
    Repo.all(
      from i in ArticleItem, where: i.article_id == ^article.id, order_by: i.sequence, select: {i.id, i.label, i.link}
    )
  end

  defp saved_title(article), do: Repo.one(from a in "synctest_articles", where: a.id == ^article.id, select: a.title)

  for kind <- ["with blocks", "without blocks"] do
    describe "a row added in the transformer, #{kind}" do
      test "is inserted once, then updated, left alone and deleted", %{conn: conn, article: article, stored: stored} do
        form = open(conn, article, unquote(kind))

        add_row(form, "New")
        save(form)
        assert [{a, "A", nil}, {new, "New", nil}] = rows(article)
        assert a == stored.id

        # No change to the row: the same row, untouched
        save(form, [{[form.singular, "title"], "Rows, again"}])
        await(fn -> saved_title(article) == "Rows, again" end)
        assert rows(article) == [{a, "A", nil}, {new, "New", nil}]

        # An edit updates the row
        set_field(form, dom_id_of(form, "New"), "label", "New, edited")
        save(form)
        assert rows(article) == [{a, "A", nil}, {new, "New, edited", nil}]

        # A row added after the first save is inserted once
        add_row(form, "Later")
        save(form)
        assert [{^a, "A", nil}, {^new, "New, edited", nil}, {later, "Later", nil}] = rows(article)
        save(form)
        assert rows(article) == [{a, "A", nil}, {new, "New, edited", nil}, {later, "Later", nil}]

        # Removing it deletes it once
        form |> transformer_target() |> render_hook("remove_entry", %{"dom_id" => dom_id_of(form, "New, edited")})
        save(form)
        assert rows(article) == [{a, "A", nil}, {later, "Later", nil}]
        save(form)
        assert rows(article) == [{a, "A", nil}, {later, "Later", nil}]
      end

      test "is kept by later saves after a refused save is corrected", %{conn: conn, article: article} do
        form = open(conn, article, unquote(kind))

        dom_id = add_row(form, "New")
        set_field(form, dom_id, "link", @unsafe)
        save(form)
        assert [{_a, "A", nil}] = rows(article)

        set_field(form, dom_id, "link", "<p>Row</p>")
        save(form)
        assert [{a, "A", nil}, {new, "New", "<p>Row</p>"}] = rows(article)

        save(form)
        assert rows(article) == [{a, "A", nil}, {new, "New", "<p>Row</p>"}]
      end
    end
  end

  describe "a row added with the entry, with blocks" do
    # The create stays on the form (`push_patch` to the entry's update
    # route); the form without blocks navigates to it instead.
    test "is kept by the next save", %{conn: conn} do
      tab = %{"brando_tab" => "reel", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
      {view, _} = conn |> put_connect_params(tab) |> live_form("/admin/reels/create", "reel_form")
      form = %{view: view, id: "reel_form", singular: "reel"}
      await(fn -> form_assigns(view, "reel_form").tab_editing? end)

      add_row(form, "New")
      save(form, [{["reel", "title"], "Reel"}])
      reel = Repo.one!(from a in "synctest_articles", where: a.title == "Reel", select: %{id: a.id})
      assert_patch(view, "/admin/reels/update/#{reel.id}")
      assert [{new, "New", nil}] = rows(reel)

      save(form)
      assert rows(reel) == [{new, "New", nil}]
    end
  end

  describe "a row's listing card" do
    test "shows the row as saved after the save", %{conn: conn, article: article, stored: stored} do
      tab = %{"brando_tab" => "reel", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
      {view, _} = conn |> put_connect_params(tab) |> live_form("/admin/reels/update/#{article.id}", "reel_form")
      form = %{view: view, id: "reel_form", singular: "reel"}
      await(fn -> form_assigns(view, "reel_form").tab_editing? end)

      dom_id = add_row(form, "New")
      refute has_element?(view, "##{dom_id} .saved-row")

      # The editor has the other row open, and edited, during the save
      open = "transformer-item-#{stored.id}"
      form |> transformer_target() |> render_hook("toggle_entry", %{"dom_id" => open})
      set_field(form, open, "label", "A, edited")

      save(form)
      assert [{_, "A, edited", nil}, {new, "New", nil}] = rows(article)
      assert has_element?(view, ~s{##{dom_id} .saved-row[data-row-id="#{new}"]})
      assert has_element?(view, ~s{##{open} .subform-fields input[value="A, edited"]})
    end
  end

  describe "a revision refused for a row, without blocks" do
    # What the live preview reads once the corrected revision is stored. The
    # refused changeset stays in the form (`store_revision/2`); the preview,
    # and a shared preview, put the transformer's rows over it
    # (`updated_entry_assocs`), which the transformer sends on each edit.
    test "leaves the live preview reading the corrected row", %{conn: conn, article: article, stored: stored} do
      form = open(conn, article, "without blocks")
      revisions = fn -> Repo.aggregate(from(r in Brando.Revisions.Revision, where: r.entry_id == ^article.id), :count) end
      before = revisions.()
      dom_id = "transformer-item-#{stored.id}"

      set_field(form, dom_id, "link", @unsafe)
      form |> form_target() |> render_hook("store_revision", %{})
      assert_push_event(form.view, "b:scroll_to_first_error", %{}, 5_000)
      assert revisions.() == before

      set_field(form, dom_id, "link", "<p>Corrected</p>")
      form |> form_target() |> render_hook("store_revision", %{})
      await(fn -> revisions.() == before + 1 end)

      form |> form_target() |> render_hook("open_live_preview", %{})
      assert_push_event(form.view, "b:live_preview", %{cache_key: key}, 5_000)
      assert {:ok, html} = Brando.LivePreview.get_cache(key)
      assert html =~ "&lt;p&gt;Corrected&lt;/p&gt;"
      refute html =~ "onclick"
    end
  end

  describe "the save without blocks" do
    # The browser sends each `b:submit`'s token once; the same token again
    # is a save that wrote already, and the save with blocks ignores it
    test "does not write again for a token already used", %{conn: conn, article: article} do
      form = open(conn, article, "without blocks")
      token = save(form, [{["album", "title"], "Saved once"}])
      await(fn -> saved_title(article) == "Saved once" end)

      # The editor types on, unsaved, and the form is to stay open on a write
      params = form.view |> render() |> form_params("#album_form_form") |> put_in(["album", "title"], "Typed")
      form.view |> element("#album_form_form") |> render_change(Map.put(params, "_target", ["album", "title"]))
      form |> form_target() |> render_hook("save_redirect_target", %{})

      form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form, []), "token" => token})

      # Were the form to ask for the rows again, the browser would answer
      receive do
        {_ref, {:push_event, "b:submit", %{token: again}}} ->
          form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form, []), "token" => again})
      after
        500 -> :ok
      end

      settle(form.view)
      assert saved_title(article) == "Saved once"
    end
  end

  describe "a plain save, twice, with no transformer" do
    test "of an entry with blocks writes each time", %{conn: conn, article: article, stored: stored} do
      tab = %{"brando_tab" => "plain", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
      {view, _} = conn |> put_connect_params(tab) |> live_form("/admin/articles/update/#{article.id}", "article_form")
      form = %{view: view, id: "article_form", singular: "article"}
      await(fn -> form_assigns(view, "article_form").tab_editing? end)

      for title <- ["First", "Second"] do
        save(form, [{["article", "title"], title}])
        await(fn -> saved_title(article) == title end)
        assert rows(article) == [{stored.id, "A", nil}]
      end
    end

    test "of an entry without blocks writes each time", %{conn: conn, article: article, stored: stored} do
      tab = %{"brando_tab" => "plain", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
      {view, _} = conn |> put_connect_params(tab) |> live_form("/admin/shelves/update/#{article.id}", "shelf_form")
      form = %{view: view, id: "shelf_form", singular: "shelf"}
      await(fn -> form_assigns(view, "shelf_form").tab_editing? end)

      for title <- ["First", "Second"] do
        # One push writes: there is nothing to collect
        form
        |> form_target()
        |> render_hook("save_form", %{"form" => browser_form(form, [{["shelf", "title"], title}]), "stay" => true})

        await(fn -> saved_title(article) == title end)
        assert rows(article) == [{stored.id, "A", nil}]
      end
    end
  end
end
