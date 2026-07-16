defmodule Brando.Pages.FragmentQueryTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Pages.FragmentQuery

  test "lists non-deleted fragments in canonical rendering order" do
    second =
      Factory.insert(:fragment,
        key: "second",
        parent_key: "parent",
        language: "no",
        sequence: 2
      )

    first =
      Factory.insert(:fragment,
        key: "first",
        parent_key: "parent",
        language: "en",
        sequence: 1
      )

    _deleted =
      Factory.insert(:fragment,
        key: "deleted",
        parent_key: "parent",
        deleted_at: DateTime.utc_now()
      )

    assert {:ok, fragments} = FragmentQuery.list_for_rendering()
    assert Enum.map(fragments, & &1.id) == [first.id, second.id]
  end
end
