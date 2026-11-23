defmodule BrandoAdmin.TransformerAddressPromptTest do
  # B saves a new transformer row with a change of the entry's address, and
  # the form asks whether to redirect the old address. While B's prompt is
  # open, A saves the entry. B's form takes A's save once B answers, as it
  # takes a save that lands during its own (TransformerSavedElsewhereTest):
  # B's row shows once, and B's next save stores it once. Before, B's
  # transformer took A's save while the prompt was open, with B's row still
  # new in it: the row showed twice, and B's next save stored it again.
  #
  # Each save is the browser's, as in TransformerSavedElsewhereTest: a first
  # `save_form` collects the rows (and blocks), the second, with the token
  # from `b:submit`, writes. Answering the prompt changes the SEO redirects,
  # whose cache is the node's: not async.
  use Brando.LiveCase, async: false

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Transformer

  setup %{conn: conn, current_user: me} do
    preserve_cache(:seo)

    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Rows",
          slug: "rows",
          language: "en",
          status: "published",
          items: [%{label: "A", sequence: 0}, %{label: "B", sequence: 1}]
        },
        me
      )

    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
    %{article: article, a_conn: conn, b_conn: other_conn}
  end

  @forms %{
    "with blocks" => {"/admin/reels/update/:id", "reel_form", "reel"},
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

    form
    |> transformer_target()
    |> render_hook("update_field", %{"dom_id" => dom_id, "field" => "label", "value" => label})
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

  # The first `save_form` collects the rows; the second, with the token
  # from `b:submit`, writes
  defp save(form, changes \\ []) do
    form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form, changes), "stay" => true})
    assert_push_event(form.view, "b:submit", %{token: token}, 5_000)
    form |> form_target() |> render_hook("save_form", %{"form" => browser_form(form, changes), "token" => token})
    settle(form.view)
  end

  defp save_title(form, article, title) do
    save(form, [{[form.singular, "title"], title}])
    await(fn -> saved_title(article) == title end)
  end

  defp prompt(%{view: view, id: id}), do: form_assigns(view, id).pending_permalink_redirect

  defp answer(form, event) do
    form |> form_target() |> render_hook(event, %{})
    settle(form.view)
  end

  defp rows(article) do
    Repo.all(from i in ArticleItem, where: i.article_id == ^article.id, order_by: i.sequence, select: {i.label, i.id})
  end

  defp form_title(%{view: view, id: id}), do: Ecto.Changeset.get_field(form_assigns(view, id).form.source, :title)

  defp saved_title(article), do: Repo.one(from a in "synctest_articles", where: a.id == ^article.id, select: a.title)

  # B saves a new row with a new address, and A saves while B's prompt is
  # open: A's change of the title, or A's own new row
  defp save_under_prompt(a, b, article, a_saves) do
    add_row(b, "From B")
    save(b, [{[b.singular, "slug"], "moved"}])
    assert prompt(b)
    [{"A", a_id}, {"B", b_id}, {"From B", from_b}] = rows(article)

    await(fn -> Enum.map(shown(a), &elem(&1, 0)) == ["A", "B", "From B"] end)
    a_saves.(a)
    settle(b.view)

    {a_id, b_id, from_b}
  end

  for kind <- ["with blocks", "without blocks"] do
    describe "#{kind}, A saving while B's address prompt is open" do
      test "shows B's new row once, and B's next save stores it once",
           %{a_conn: a_conn, b_conn: b_conn, article: article} do
        a = open(a_conn, article, unquote(kind), "a")
        b = open(b_conn, article, unquote(kind), "b")

        {a_id, b_id, from_b} = save_under_prompt(a, b, article, &save_title(&1, article, "Saved by A"))
        assert Enum.map(shown(b), &elem(&1, 0)) == ["A", "B", "From B"]

        answer(b, "skip_permalink_redirect")
        assert shown(b) == [{"A", a_id}, {"B", b_id}, {"From B", from_b}]
        assert form_title(b) == "Saved by A"

        save_title(b, article, "Saved by B")
        assert rows(article) == [{"A", a_id}, {"B", b_id}, {"From B", from_b}]
      end

      for event <- ["skip_permalink_redirect", "create_permalink_redirect"] do
        test "#{event}: shows the stored rows once, A's new row too",
             %{a_conn: a_conn, b_conn: b_conn, article: article} do
          a = open(a_conn, article, unquote(kind), "a")
          b = open(b_conn, article, unquote(kind), "b")

          a_saves = fn a ->
            add_row(a, "From A")
            save(a)
            await(fn -> length(rows(article)) == 4 end)
          end

          save_under_prompt(a, b, article, a_saves)
          answer(b, unquote(event))
          refute prompt(b)

          saved = rows(article)
          assert [{"A", _}, {"B", _}, {"From B", _}, {"From A", _}] = saved
          assert shown(b) == saved

          save_title(b, article, "Saved by B")
          assert rows(article) == saved
          assert shown(b) == saved
        end
      end
    end
  end
end
