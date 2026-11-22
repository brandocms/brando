defmodule BrandoAdmin.EmbedRowSyncTest do
  # Two editors in an article's embeds_many rows (`quotes`, a rich text per
  # row), through real LiveViews: inline on the `rich_quotes` form, as a
  # listing on `quote_listing`. A row one editor adds, inserts, removes or
  # moves reaches the other editor at the click, as the whole relation
  # (#3757, #3805). Synchronous, as EntryFieldSyncTest: both editors'
  # Presence lookups outlive an async test's sandbox.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.SyncTest
  alias BrandoAdmin.Components.Form.Input.SubformHelpers

  @rows ["<p>Første</p>", "<p>Andre</p>", "<p>Tredje</p>"]

  setup %{current_user: me} do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Sitater",
          slug: "sitater",
          language: "no",
          status: "published",
          quotes: Enum.map(@rows, &%{text: &1})
        },
        me
      )

    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    %{article: article, other_conn: log_in_user(Phoenix.ConnTest.build_conn(), other)}
  end

  defp open(conn, article, form) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/#{form}", "article_form")
    view
  end

  defp editors(%{conn: conn, article: article, other_conn: other_conn}, form),
    do: {open(conn, article, form), open(other_conn, article, form)}

  defp form(view), do: with_target(view, cid_of(view, "#article_form-el"))

  defp params(view), do: view |> render() |> form_params("#article_form_form")

  defp quotes(view) do
    view
    |> params()
    |> get_in(["article", "quotes"])
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} -> row["text"] end)
  end

  defp form_assigns(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BrandoAdmin.Components.Form, _id, assigns, _private, _prints}} -> assigns
      _ -> nil
    end)
  end

  # A keystroke as the browser sends it: the whole form, one field changed
  defp type(view, path, value) do
    path = ["article" | path]
    params = view |> params() |> put_in(path, value) |> Map.put("_target", path)
    view |> element("#article_form_form") |> render_change(params)
  end

  defp add_row(view), do: view |> element(".add-entry-button") |> render_click()

  defp insert_row(view, index), do: view |> element("#article_quotes_#{index}-entry .subform-insert") |> render_click()

  # As the browser sends a click on a row's remove button: every row's
  # inputs stay in the form, and the button's value joins the drop param
  # (`Brando.TableRows` copies it into a hidden input in the row, ahead of
  # the subform's empty one)
  defp remove_row(view, index) do
    params =
      view
      |> params()
      |> put_in(["article", "drop_quotes_ids"], [to_string(index), ""])
      |> Map.put("_target", ["article", "drop_quotes_ids"])

    view |> form() |> render_hook("validate", params)
  end

  # As `Brando.SortableEmbeds` sends a drop: the rows' keys in their new order
  defp reorder(view, order) do
    keys = SubformHelpers.row_keys(form_assigns(view).form.source, :quotes)

    view
    |> with_target(cid_of(view, "#article_quotes-sortable"))
    |> render_hook("sequenced_subform", %{"ids" => Enum.map(order, &Enum.at(keys, &1)), "embeds" => true})
  end

  for form <- ["rich_quotes", "quote_listing"] do
    describe "on #{form}, a row the other editor" do
      @describetag form: form

      test "adds reaches this editor at the click", %{form: form} = c do
        {a, b} = editors(c, form)

        add_row(a)
        assert length(quotes(a)) == 4
        await(fn -> length(quotes(b)) == 4 end)
        assert Enum.take(quotes(b), 3) == @rows
      end

      test "removes reaches this editor at the click", %{form: form} = c do
        {a, b} = editors(c, form)
        assert quotes(b) == @rows

        remove_row(a, 1)
        assert quotes(a) == ["<p>Første</p>", "<p>Tredje</p>"]
        await(fn -> quotes(b) == ["<p>Første</p>", "<p>Tredje</p>"] end)
        assert Process.alive?(b.pid)
      end

      test "moves reaches this editor at the click", %{form: form} = c do
        {a, b} = editors(c, form)

        reorder(a, [2, 0, 1])
        assert quotes(a) == ["<p>Tredje</p>", "<p>Første</p>", "<p>Andre</p>"]
        await(fn -> quotes(b) == ["<p>Tredje</p>", "<p>Første</p>", "<p>Andre</p>"] end)
      end
    end
  end

  test "a row the other editor inserts reaches this editor at the click", c do
    {a, b} = editors(c, "rich_quotes")

    insert_row(a, 1)
    assert [_, nil, _, _] = quotes(a) |> Enum.map(&blank_to_nil/1)
    await(fn -> length(quotes(b)) == 4 end)
    assert ["<p>Første</p>", blank, "<p>Andre</p>", "<p>Tredje</p>"] = quotes(b)
    assert blank_to_nil(blank) == nil
  end

  # The relation ships as one value: while a row's text is refused, an added
  # row waits with it (#3790)
  test "a row added beside a refused one waits with it", c do
    {a, b} = editors(c, "rich_quotes")

    type(a, ["quotes", "1", "text"], ~s{<p><a href="javascript:alert(1)">link</a></p>})
    add_row(a)
    assert length(quotes(a)) == 4
    assert Brando.RichText.refused?(form_assigns(a).form.source, :quotes)

    Enum.each([a, b, a, b], &settle/1)
    assert quotes(b) == @rows
  end

  # A change to the relation the editor is in waits until they leave it,
  # so the row they type in is drawn as it was, their text and focus kept
  for op <- [:add, :remove] do
    @tag op: op
    test "an editor typing in a row keeps the row and their text when the other editor's #{op} arrives", c do
      {a, b} = editors(c, "rich_quotes")
      b |> form() |> render_hook("focus", %{"field" => "article[quotes][0][text]"})
      type(b, ["quotes", "0", "text"], "<p>Første, B</p>")

      if c.op == :add, do: add_row(a), else: remove_row(a, 2)
      Enum.each([a, b, a, b], &settle/1)

      assert form_assigns(b).focused_field == "article[quotes][0][text]"
      assert hd(quotes(b)) == "<p>Første, B</p>"
      assert Map.has_key?(form_assigns(b).held_remote, :quotes)
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
