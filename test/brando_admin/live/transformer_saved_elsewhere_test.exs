defmodule BrandoAdmin.TransformerSavedElsewhereTest do
  # Two editors in one entry with a transformer subform; A saves. B's
  # transformer takes the rows A saved, keeping B's own unsaved changes to
  # them, so B's next save leaves A's rows as A saved them. Before, B's
  # transformer kept the rows it loaded at mount, and B's save put them back:
  # it deleted the rows A added and inserted again the rows A removed.
  #
  # Each save is the browser's, as in TransformerSavesTest: a first
  # `save_form` collects the rows (and blocks), the second, with the token
  # from `b:submit`, writes.
  use Brando.LiveCase, async: true

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Transformer

  setup %{conn: conn, current_user: me} do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Rows",
          slug: "rows",
          language: "en",
          status: "published",
          items: [%{label: "A", sequence: 0}, %{label: "B", sequence: 1}, %{label: "C", sequence: 2}]
        },
        me
      )

    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
    %{article: article, a_conn: conn, b_conn: other_conn}
  end

  @forms %{
    "with blocks" => {"/admin/articles/update/:id/transformer_rich_items", "article_form", "article"},
    "without blocks" => {"/admin/albums/update/:id", "album_form", "album"}
  }

  defp open(conn, article, kind, tab) do
    {path, id, singular} = Map.fetch!(@forms, kind)
    params = %{"brando_tab" => tab, "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}

    {view, _} =
      conn |> put_connect_params(params) |> live_form(String.replace(path, ":id", to_string(article.id)), id)

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

  # The sticky UploadManager hands a finished upload to the transformer
  defp deliver_upload(%{view: view} = form, ref, asset) do
    Phoenix.LiveView.send_update(view.pid, Transformer,
      id: transformer(form).id,
      event: "upload_complete",
      ref: ref,
      asset: asset
    )

    settle(view)
  end

  # The stream updates a LiveView sends its browser while `fun` runs
  defp watch_streams(%{view: view}, fun) do
    :erlang.trace(view.pid, true, [:send])
    fun.()
    settle(view)
    :erlang.trace(view.pid, false, [:send])
    collect_streams([])
  end

  # A stream update that draws cards: inserts, deletes or a reset
  defp drawn?([_ref, inserts, deletes | reset]), do: inserts != [] or deletes != [] or reset == [true]

  defp collect_streams(acc) do
    receive do
      {:trace, _pid, :send, %Phoenix.Socket.Message{event: "diff", payload: diff}, _to} ->
        collect_streams(acc ++ streams_in(diff))

      {:trace, _pid, :send, %Phoenix.Socket.Reply{payload: %{diff: diff}}, _to} ->
        collect_streams(acc ++ streams_in(diff))

      {:trace, _pid, :send, _message, _to} ->
        collect_streams(acc)
    after
      0 -> acc
    end
  end

  defp streams_in(%{} = diff) do
    Enum.flat_map(diff, fn
      {:stream, stream} -> [stream]
      {_key, value} -> streams_in(value)
    end)
  end

  defp streams_in(list) when is_list(list), do: Enum.flat_map(list, &streams_in/1)
  defp streams_in(_term), do: []

  defp remove_row(form, label),
    do: form |> transformer_target() |> render_hook("remove_entry", %{"dom_id" => dom_id_of(form, label)})

  defp reorder(form, labels),
    do:
      form |> transformer_target() |> render_hook("sequenced_subform", %{"ids" => Enum.map(labels, &dom_id_of(form, &1))})

  defp dom_id_of(form, label) do
    Enum.find_value(transformer(form).items, fn item -> if shown_label(item) == label, do: item.dom_id end)
  end

  defp shown_label(item), do: Map.merge(Map.new(Map.take(item.source, [:label])), item.changes)[:label]

  # The rows the transformer shows: label, and id once saved
  defp shown(form), do: Enum.map(transformer(form).items, &{shown_label(&1), if(!&1.is_new, do: &1.source.id)})

  defp browser_form(%{view: view, id: id}, changes) do
    view
    |> render()
    |> form_params("##{id}_form")
    |> then(&Enum.reduce(changes, &1, fn {path, value}, acc -> put_in(acc, path, value) end))
    |> Plug.Conn.Query.encode()
  end

  defp save(form, changes \\ []) do
    form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form, changes), "stay" => true})
    assert_push_event(form.view, "b:submit", %{token: token}, 5_000)
    form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form, changes), "token" => token})
    settle(form.view)
  end

  # B saves a field outside the transformer
  defp save_title(form, article, title) do
    save(form, [{[form.singular, "title"], title}])
    await(fn -> saved_title(article) == title end)
  end

  # B's recovery copy, as the browser captures it while B types
  defp capture(form) do
    params = %{"main" => browser_form(form, []), "blocks" => %{}, "generation" => 1, "request_id" => 1}
    form |> form_target() |> render_hook("draft_capture", params)
  end

  defp latest_copy(article) do
    Repo.one(
      from d in Brando.Drafts.EntryDraft,
        where: d.entry_id == ^article.id and is_nil(d.resolved_at),
        order_by: [desc: d.id],
        limit: 1
    )
  end

  # B's connection drops; the reopened form restores B's recovery copy
  defp reconnect_and_restore(form, conn, article, kind, tab) do
    await(fn -> latest_copy(article) != nil end)
    kill_live(form.view)
    form = open(conn, article, kind, tab)
    form |> form_target() |> render_hook("draft_restore", %{"id" => latest_copy(article).id})
    settle(form.view)
    form
  end

  defp rows(article) do
    Repo.all(from i in ArticleItem, where: i.article_id == ^article.id, order_by: i.sequence, select: {i.label, i.id})
  end

  defp form_title(%{view: view, id: id}), do: Ecto.Changeset.get_field(form_assigns(view, id).form.source, :title)

  defp saved_title(article), do: Repo.one(from a in "synctest_articles", where: a.id == ^article.id, select: a.title)

  # B has taken A's save once its transformer shows the rows A saved
  defp await_taken(b, rows), do: await(fn -> shown(b) == rows end)

  for kind <- ["with blocks", "without blocks"] do
    describe "#{kind}, B with no unsaved change in the transformer" do
      test "keeps a row A added, with its id", %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")

        add_row(a, "D")
        save(a)
        saved = rows(article)
        assert [{"A", _}, {"B", _}, {"C", _}, {"D", _}] = saved

        await_taken(b, saved)
        save_title(b, article, "Saved by B")
        assert rows(article) == saved
      end

      test "leaves a row A removed gone", %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")

        remove_row(a, "B")
        save(a)
        saved = rows(article)
        assert [{"A", _}, {"C", _}] = saved

        await_taken(b, saved)
        save_title(b, article, "Saved by B")
        assert rows(article) == saved
      end

      test "keeps A's order and values", %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")

        set_field(a, dom_id_of(a, "A"), "label", "A, by A")
        reorder(a, ["C", "A, by A", "B"])
        save(a)
        saved = rows(article)
        assert [{"C", _}, {"A, by A", _}, {"B", _}] = saved

        await_taken(b, saved)
        save_title(b, article, "Saved by B")
        assert rows(article) == saved
      end
    end

    describe "#{kind}, B with unsaved changes in the transformer" do
      test "keeps B's new row and the row A added", %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")
        add_row(b, "From B")

        add_row(a, "From A")
        save(a)
        [{"A", a_id}, {"B", b_id}, {"C", c_id}, {"From A", from_a}] = rows(article)

        await_taken(b, [{"A", a_id}, {"B", b_id}, {"C", c_id}, {"From A", from_a}, {"From B", nil}])
        save_title(b, article, "Saved by B")
        assert [{"A", ^a_id}, {"B", ^b_id}, {"C", ^c_id}, {"From A", ^from_a}, {"From B", _}] = rows(article)
      end

      test "keeps B's edit and removal, A's new row, and drops the row A removed",
           %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")
        set_field(b, dom_id_of(b, "A"), "label", "A, by B")
        remove_row(b, "C")

        remove_row(a, "B")
        add_row(a, "From A")
        save(a)
        [{"A", a_id}, {"C", _}, {"From A", from_a}] = rows(article)

        await_taken(b, [{"A, by B", a_id}, {"From A", from_a}])
        save_title(b, article, "Saved by B")
        assert rows(article) == [{"A, by B", a_id}, {"From A", from_a}]
      end

      test "keeps B's order, with A's new row after the row it follows",
           %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")
        reorder(b, ["C", "B", "A"])

        set_field(a, dom_id_of(a, "B"), "label", "B, by A")
        add_row(a, "From A")
        save(a)
        [{"A", a_id}, {"B, by A", b_id}, {"C", c_id}, {"From A", from_a}] = rows(article)

        await_taken(b, [{"C", c_id}, {"From A", from_a}, {"B, by A", b_id}, {"A", a_id}])
        save_title(b, article, "Saved by B")
        assert rows(article) == [{"C", c_id}, {"From A", from_a}, {"B, by A", b_id}, {"A", a_id}]
      end

      # As a field both editors changed: B's unsaved value stays, and B's
      # save writes it.
      test "keeps B's value in a field A changed too", %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")
        set_field(b, dom_id_of(b, "A"), "label", "A, by B")

        set_field(a, dom_id_of(a, "A"), "label", "A, by A")
        set_field(a, dom_id_of(a, "B"), "label", "B, by A")
        save(a)
        [{"A, by A", a_id}, {"B, by A", b_id}, {"C", c_id}] = rows(article)

        await_taken(b, [{"A, by B", a_id}, {"B, by A", b_id}, {"C", c_id}])
        save_title(b, article, "Saved by B")
        assert rows(article) == [{"A, by B", a_id}, {"B, by A", b_id}, {"C", c_id}]
      end
    end
  end

  for kind <- ["with blocks", "without blocks"] do
    describe "#{kind}, B's edit restored after a reconnect" do
      # The restored copy is B's unsaved edit as any other: A's save of
      # another field leaves it in B's row, and B's save writes it.
      test "stays B's after A saves another field", %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")
        set_field(b, dom_id_of(b, "A"), "label", "A, by B")
        capture(b)
        b = reconnect_and_restore(b, b_conn, article, unquote(kind), "b")
        [{"A", a_id}, {"B", b_id}, {"C", c_id}] = rows(article)
        await_taken(b, [{"A, by B", a_id}, {"B", b_id}, {"C", c_id}])

        save_title(a, article, "Saved by A")
        await(fn -> form_title(b) == "Saved by A" end)
        settle(b.view)
        assert shown(b) == [{"A, by B", a_id}, {"B", b_id}, {"C", c_id}]

        save_title(b, article, "Saved by B")
        assert rows(article) == [{"A, by B", a_id}, {"B", b_id}, {"C", c_id}]
      end
    end
  end

  describe "B replacing the file of a row A removed" do
    test "stops the upload, and the file that lands adds no row", %{a_conn: a_conn, b_conn: b_conn, article: article} do
      a = open(a_conn, article, "without blocks", "a")
      b = open(b_conn, article, "without blocks", "b")
      file = %{"ref" => "tf-replaceb", "filename" => "new.jpg", "size" => 10, "kind" => "image"}
      b |> transformer_target() |> render_hook("register_replacement", %{"dom_id" => dom_id_of(b, "B"), "file" => file})

      remove_row(a, "B")
      save(a)
      [{"A", a_id}, {"C", c_id}] = rows(article)

      await_taken(b, [{"A", a_id}, {"C", c_id}])
      assert_push_event(b.view, "transformer:abort_upload", %{ref: "tf-replaceb"})

      image = Factory.insert(:image)
      deliver_upload(b, "tf-replaceb", image)
      assert shown(b) == [{"A", a_id}, {"C", c_id}]

      save_title(b, article, "Saved by B")
      assert rows(article) == [{"A", a_id}, {"C", c_id}]
    end
  end

  for kind <- ["with blocks", "without blocks"] do
    describe "#{kind}, A saving another field" do
      # A redraw would wipe what the browser put on B's cards (a drag in
      # progress, a drop highlight).
      test "leaves B's listing as it is drawn", %{a_conn: a_conn, b_conn: b_conn, article: article} do
        image = Factory.insert(:image)

        Repo.update_all(from(i in ArticleItem, where: i.article_id == ^article.id and i.label == "B"),
          set: [cover_id: image.id]
        )

        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")
        set_field(b, dom_id_of(b, "A"), "label", "A, by B")

        streams =
          watch_streams(b, fn ->
            save_title(a, article, "Saved by A")
            await(fn -> form_title(b) == "Saved by A" end)
          end)

        assert Enum.filter(streams, &drawn?/1) == []
        assert Enum.map(shown(b), &elem(&1, 0)) == ["A, by B", "B", "C"]
        assert Enum.map(transformer(b).items, &(&1.assets.cover && &1.assets.cover.id)) == [nil, image.id, nil]
      end
    end
  end

  describe "B's own saved change" do
    # A value B saved stays in the item's changes after the save; A's later
    # change to it is not B's to undo.
    test "does not undo A's later change to it", %{a_conn: a_conn, b_conn: b_conn, article: article} do
      a = open(a_conn, article, "without blocks", "a")
      b = open(b_conn, article, "without blocks", "b")

      set_field(b, dom_id_of(b, "A"), "label", "A, by B")
      save(b)
      [{"A, by B", a_id}, {"B", b_id}, {"C", c_id}] = rows(article)

      await(fn -> Enum.map(shown(a), &elem(&1, 0)) == ["A, by B", "B", "C"] end)
      set_field(a, dom_id_of(a, "A, by B"), "label", "A, by A")
      save(a)
      assert rows(article) == [{"A, by A", a_id}, {"B", b_id}, {"C", c_id}]

      await_taken(b, [{"A, by A", a_id}, {"B", b_id}, {"C", c_id}])
      save_title(b, article, "Saved by B")
      assert rows(article) == [{"A, by A", a_id}, {"B", b_id}, {"C", c_id}]
    end
  end
end
