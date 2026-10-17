defmodule BrandoAdmin.Components.Form.Input.SelectUpdateRelationTest do
  # A select's `update_relation: {relation, fetcher}` puts what the fetcher
  # returns on the relation. Fetchers are written both ways: `{:ok, record}`
  # (as documented) and the record itself (a `get_x!` query, as
  # `Brando.Content.Container.get_palette/1` is).
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Input.Select

  test "a fetcher may return the record or {:ok, record}" do
    record = %Brando.Pages.Page{id: 1, title: "Example Hotel"}

    assert Select.fetch_relation("1", fn "1" -> {:ok, record} end) == record
    assert Select.fetch_relation("1", fn "1" -> record end) == record
    assert Select.fetch_relation("1", fn "1" -> {:error, :not_found} end) == nil
    assert Select.fetch_relation(nil, fn _ -> record end) == nil
  end

  # A `get_x!` fetcher raises for a record deleted since, or one the
  # editor may not read; the relation is then empty, not the form gone.
  test "a fetcher that finds no record gives no record" do
    assert Select.fetch_relation("1", fn _ -> raise Ecto.NoResultsError, queryable: Brando.Pages.Page end) == nil
  end

  test "a container's palette select puts the palette on the relation" do
    palette = Factory.insert(:palette)

    assert %Brando.Content.Palette{id: id} =
             Select.fetch_relation(to_string(palette.id), &Brando.Content.Container.get_palette/1)

    assert id == palette.id
  end
end
