defmodule BrandoAdmin.Components.Form.Input.SubformHelpersTest do
  # Regression coverage for B6 — adding, removing or reordering a subform row
  # discarded pending input on its SIBLING rows.
  #
  # The handlers rebuilt the relation list with `Ecto.Changeset.get_field/3`.
  # The subtlety is that `get_field/3` DOES carry the pending value: it returns
  # applied structs, so the typed text is right there in the struct. What is
  # lost is the *change* — writing structs back produces child changesets with
  # empty `changes`, the struct just becomes the new `data`, and Ecto has
  # nothing to write. The row silently reverts at save.
  #
  # Same root cause as the ref media FKs (B1): a value in `data` rather than in
  # `changes` never reaches SQL.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Var
  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    entry_block =
      %Brando.Pages.Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "subformblk",
        type: :module,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        vars: [
          %{type: :string, key: "one", label: "One", value: "orig1", placement: :content, width: :full},
          %{type: :string, key: "two", label: "Two", value: "orig2", placement: :content, width: :full}
        ]
      })
      |> Brando.Repo.insert!()
      |> Brando.Repo.preload(block: :vars)

    block = entry_block.block
    [v1, v2] = Enum.sort_by(block.vars, & &1.key)

    # the user has typed into row "one" but not blurred — a pending nested change
    pending =
      block
      |> Changeset.change()
      |> Changeset.put_assoc(:vars, [
        Changeset.change(v1, %{value: "PENDING"}),
        Changeset.change(v2)
      ])

    {:ok, block: block, pending: pending}
  end

  defp values(changeset) do
    changeset
    |> Changeset.get_assoc(:vars)
    |> Enum.reject(&(&1.action == :replace))
    |> Map.new(&{Changeset.get_field(&1, :key), Changeset.get_field(&1, :value)})
  end

  defp persisted_values(changeset) do
    {:ok, saved} = changeset |> Map.put(:action, nil) |> Brando.Repo.update()

    saved
    |> Brando.Repo.preload(:vars, force: true)
    |> Map.get(:vars)
    |> Map.new(&{&1.key, &1.value})
  end

  test "current_entries/2 returns changesets, not applied structs", %{pending: pending} do
    entries = SubformHelpers.current_entries(pending, :vars)

    assert Enum.all?(entries, &is_struct(&1, Changeset))

    # the pending edit is a real change, not merely applied into the data
    edited = Enum.find(entries, &(Changeset.get_field(&1, :key) == "one"))
    assert edited.changes[:value] == "PENDING"
  end

  test "appending a row keeps pending input on the existing rows", %{pending: pending} do
    new_var = Changeset.change(%Var{type: :string, key: "three", label: "Three", value: "new", placement: :content})

    updated =
      SubformHelpers.put_entries(
        pending,
        :vars,
        SubformHelpers.current_entries(pending, :vars) ++ [new_var]
      )

    assert values(updated)["one"] == "PENDING"
    assert persisted_values(updated) == %{"one" => "PENDING", "two" => "orig2", "three" => "new"}
  end

  test "removing a row keeps pending input on the remaining rows", %{pending: pending} do
    entries = SubformHelpers.current_entries(pending, :vars)
    index = Enum.find_index(entries, &(Changeset.get_field(&1, :key) == "two"))

    updated = SubformHelpers.put_entries(pending, :vars, List.delete_at(entries, index))

    assert values(updated)["one"] == "PENDING"
    assert persisted_values(updated) == %{"one" => "PENDING"}
  end

  test "reordering keeps pending input", %{pending: pending} do
    entries = SubformHelpers.current_entries(pending, :vars)

    updated = SubformHelpers.put_entries(pending, :vars, Enum.reverse(entries))

    assert values(updated)["one"] == "PENDING"
    assert persisted_values(updated)["one"] == "PENDING"
  end

  test "the old get_field/put_change path is what loses the edit", %{pending: pending} do
    # documents the exact defect, so a regression is unambiguous
    entries = Changeset.get_field(pending, :vars)

    # get_field DOES show the pending value...
    assert Enum.find(entries, &(&1.key == "one")).value == "PENDING"

    # ...but writing structs back produces no changes, so nothing is persisted
    stale = Changeset.put_assoc(pending, :vars, entries)

    assert stale
           |> Changeset.get_assoc(:vars)
           |> Enum.all?(&(&1.changes == %{}))

    assert persisted_values(stale)["one"] == "orig1"
  end
end
