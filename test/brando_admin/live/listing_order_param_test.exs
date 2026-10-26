defmodule BrandoAdmin.ListingOrderParamTest do
  # A listing's `?order=` comes from the URL, which any signed-in user can
  # write. It names the schema's fields, or it is ignored; it never becomes
  # new atoms, which are never freed and stop the node when the table is full.
  use Brando.LiveCase

  setup %{current_user: user} do
    ids =
      Map.new(~w(Beta Alpha Gamma), fn title ->
        {:ok, article} =
          Brando.SyncTest.create_article(
            %{title: title, slug: String.downcase(title), language: "en", status: "published"},
            user
          )

        {"list-row-#{article.id}", title}
      end)

    {:ok, ids: ids}
  end

  defp fresh, do: "zz_no_atom_#{System.unique_integer([:positive])}"

  defp atom?(string) do
    _ = String.to_existing_atom(string)
    true
  rescue
    ArgumentError -> false
  end

  defp open(conn, query) do
    {:ok, view, _html} = live(conn, "/admin/articles?" <> query)
    await_selector(view, ".content-list .list-row")
    view
  end

  # The rows show no titles: they go by the article's row id
  defp titles(view, ids) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(".content-list .list-row")
    |> Enum.map(&ids[&1 |> Floki.attribute("id") |> List.first()])
  end

  test "names that are no field make no atom, and the default sort stays", %{conn: conn, ids: ids} do
    [a, b, c, d, e] = names = for _ <- 1..5, do: fresh()
    view = open(conn, URI.encode_query(%{"order" => "asc #{a}, desc #{b}.#{c}, #{d} #{e}"}))

    refute Enum.any?(names, &atom?/1)
    # The listing's default order: by id
    assert titles(view, ids) == ~w(Beta Alpha Gamma)

    grouped = fresh()
    view = open(conn, "order[desc]=#{grouped}")
    refute atom?(grouped)
    assert titles(view, ids) == ~w(Beta Alpha Gamma)
  end

  test "the schema's fields order the rows", %{conn: conn, ids: ids} do
    assert conn |> open("order=desc+title") |> titles(ids) == ~w(Gamma Beta Alpha)
    assert conn |> open("order[asc]=title") |> titles(ids) == ~w(Alpha Beta Gamma)
  end
end
