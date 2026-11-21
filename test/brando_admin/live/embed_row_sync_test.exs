defmodule BrandoAdmin.EmbedRowSyncTest do
  # Two editors in an article's embeds_many rows (`quotes`, a rich text per
  # row; the `rich_quotes` form), through real LiveViews: a row one editor
  # removes ships with the rows that are left, and the other editor's form
  # takes them (#3757). Synchronous, as EntryFieldSyncTest: both editors'
  # Presence lookups outlive an async test's sandbox.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.SyncTest

  setup %{current_user: me, conn: conn} do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Sitater",
          slug: "sitater",
          language: "no",
          status: "published",
          quotes: [%{text: "<p>Første</p>"}, %{text: "<p>Andre</p>"}, %{text: "<p>Tredje</p>"}]
        },
        me
      )

    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)

    %{a: open(conn, article), b: open(other_conn, article)}
  end

  defp open(conn, article) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}/rich_quotes", "article_form")
    view
  end

  defp form(view), do: with_target(view, cid_of(view, "#article_form-el"))

  defp quotes(view) do
    view
    |> render()
    |> form_params("#article_form_form")
    |> get_in(["article", "quotes"])
    |> Enum.sort_by(fn {index, _row} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, row} -> row["text"] end)
  end

  test "a removed row reaches the other editor with the rows that are left", %{a: a, b: b} do
    assert quotes(b) == ["<p>Første</p>", "<p>Andre</p>", "<p>Tredje</p>"]

    params = a |> render() |> form_params("#article_form_form")
    assert params["article"]["sort_quotes_ids"] == ["0", "1", "2"]

    # As the browser sends a click on the second row's remove button: every
    # row's inputs stay in the form, and the button's value joins the drop
    # param (`Brando.TableRows` copies it into a hidden input in the row,
    # ahead of the subform's empty one)
    params =
      params
      |> put_in(["article", "drop_quotes_ids"], ["1", ""])
      |> Map.put("_target", ["article", "drop_quotes_ids"])

    a |> form() |> render_hook("validate", params)
    # A button sends no focus or blur: the removal ships when the editor
    # next leaves a field
    a |> form() |> render_hook("focus", %{"field" => "article[quotes][0][text]"})
    a |> form() |> render_hook("blur", %{"field" => "article[quotes][0][text]"})

    assert quotes(a) == ["<p>Første</p>", "<p>Tredje</p>"]
    await(fn -> quotes(b) == ["<p>Første</p>", "<p>Tredje</p>"] end)
    assert Process.alive?(b.pid)
  end
end
