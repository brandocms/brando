defmodule BrandoAdmin.EmbeddedRowsSavedElsewhereTest do
  # Two editors in one article; A saves the quotes, an embedded list stored
  # in one column, while B is working in them. B's form keeps the rows B
  # changed, added or removed, and takes A's saved values in the rest, as a
  # has_many already is kept. Before, B kept every row as its form loaded
  # them, and B's next save undid A's rows.
  #
  # B is in a quote's input when A saves: the quotes A ships wait until B
  # leaves them (`held_remote`), so what B's form holds is decided by A's
  # save reaching it (`take_saved_entry`).
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.SyncTest
  alias Brando.SyncTest.Article

  setup %{conn: conn, current_user: me} do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Quotes",
          slug: "quotes",
          language: "en",
          status: "published",
          quotes: [%{text: "One"}, %{text: "Two"}, %{text: "Three"}]
        },
        me
      )

    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    path = "/admin/articles/update/#{article.id}"
    {a, _} = live_form(conn, path, "article_form")
    {b, _} = live_form(log_in_user(Phoenix.ConnTest.build_conn(), other), path, "article_form")

    %{article: article, a: a, b: b}
  end

  defp form_of(view), do: with_target(view, cid_of(view, "#article_form-el"))

  defp params(view), do: view |> render() |> form_params("#article_form_form")

  defp focus(view, index),
    do: view |> form_of() |> render_hook("focus", %{"field" => "article[quotes][#{index}][text]"})

  # A keystroke as the browser sends it: the whole form, one field changed
  defp type(view, index, value), do: type_in(view, render(view), index, value)

  # The same, from the form as the browser showed it in `html`
  defp type_in(view, html, index, value) do
    path = ["article", "quotes", to_string(index), "text"]
    params = html |> form_params("#article_form_form") |> put_in(path, value) |> Map.put("_target", path)
    view |> element("#article_form_form") |> render_change(params)
  end

  defp subform(view), do: with_target(view, cid_of(view, ~s(input[name="article[quotes][0][text]"])))

  defp add(view), do: view |> subform() |> render_click("add_subentry", %{})

  defp remove(view, article, text) do
    %{id: id} = Enum.find(Repo.get!(Article, article.id).quotes, &(&1.text == text))
    view |> subform() |> render_click("remove_subentry", %{"key" => "id-#{id}"})
  end

  # "Save and continue editing": the first submit collects the blocks, the
  # second writes
  defp save(view) do
    view |> form_of() |> render_hook("save_redirect_target", %{})
    view |> element("#article_form_form") |> render_submit(%{})
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> element("#article_form_form") |> render_submit(%{})
  end

  defp quotes(view) do
    case get_in(params(view), ["article", "quotes"]) do
      %{} = rows -> for {_, row} <- Enum.sort_by(rows, &String.to_integer(elem(&1, 0))), do: row["text"]
      _ -> []
    end
  end

  defp stored(article), do: Enum.map(Repo.get!(Article, article.id).quotes, & &1.text)

  # A saves; B's form shows `shown` once the save reaches it, and B's save
  # stores it.
  defp a_saves_then_b(c, shown) do
    save(c.a)
    await(fn -> quotes(c.b) == shown end)

    save(c.b)
    await(fn -> stored(c.article) == shown end)
  end

  test "a row B changed stays, and the row A saved takes A's text", c do
    focus(c.b, 1)
    type(c.b, 1, "Two by B")

    type(c.a, 0, "One by A")
    a_saves_then_b(c, ["One by A", "Two by B", "Three"])
  end

  # B's browser sends a keystroke from the form it showed before A's save
  # reached it, with A's row as it was: the form keeps A's row. The input B
  # types in keeps its text while it has focus, and the next keystroke
  # sends it again.
  test "B's keystroke from the form before A's save keeps A's row", c do
    focus(c.b, 1)
    type(c.b, 1, "Two by B")
    before = render(c.b)

    type(c.a, 0, "One by A")
    save(c.a)
    await(fn -> quotes(c.b) == ["One by A", "Two by B", "Three"] end)

    type_in(c.b, before, 1, "Two by B!")
    assert quotes(c.b) == ["One by A", "Two by B", "Three"]

    type(c.b, 1, "Two by B!")
    assert quotes(c.b) == ["One by A", "Two by B!", "Three"]

    save(c.b)
    await(fn -> stored(c.article) == ["One by A", "Two by B!", "Three"] end)
  end

  test "a row B removed stays removed, though A saved a change to it", c do
    focus(c.a, 2)
    type(c.a, 2, "Three by A")

    remove(c.b, c.article, "Three")
    focus(c.b, 0)

    a_saves_then_b(c, ["One", "Two"])
  end

  test "a row B added stays", c do
    add(c.b)
    focus(c.b, 3)
    type(c.b, 3, "Four by B")

    type(c.a, 0, "One by A")
    a_saves_then_b(c, ["One by A", "Two", "Three", "Four by B"])
  end

  test "a row A added comes in beside its neighbour", c do
    focus(c.b, 0)
    type(c.b, 0, "One by B")

    focus(c.a, 1)
    add(c.a)
    type(c.a, 3, "Four by A")
    a_saves_then_b(c, ["One by B", "Two", "Three", "Four by A"])
  end

  test "a row A removed and B didn't change goes", c do
    focus(c.b, 0)
    type(c.b, 0, "One by B")

    focus(c.a, 0)
    remove(c.a, c.article, "Two")
    a_saves_then_b(c, ["One by B", "Three"])
  end

  test "a row A removed that B changed stays", c do
    focus(c.b, 1)
    type(c.b, 1, "Two by B")

    focus(c.a, 0)
    remove(c.a, c.article, "Two")
    a_saves_then_b(c, ["One", "Two by B", "Three"])
  end

  # B changed the title only
  test "quotes B didn't change take A's save whole", c do
    c.b |> element("#article_form_form") |> render_change(put_in(params(c.b), ["article", "title"], "Title by B"))

    focus(c.a, 0)
    type(c.a, 0, "One by A")
    remove(c.a, c.article, "Three")
    a_saves_then_b(c, ["One by A", "Two"])
    assert Repo.get!(Article, c.article.id).title == "Title by B"
  end
end
