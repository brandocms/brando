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

  # `PageVars` is rendered by `fieldset/field.ex` with a `field=` prop and no
  # `form=`, so a handler reading `socket.assigns.form` raises KeyError and takes
  # the LiveView down. Every subform handler must read through `:field`.
  test "subform handlers read the changeset from :field, never :form", %{block: block} do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(:field, Phoenix.Component.to_form(Changeset.change(block), as: "block")[:vars])
      |> Phoenix.Component.assign(:subform, %{name: :vars})

    refute Map.has_key?(socket.assigns, :form),
           "fixture must mirror the real component, which has no :form assign"

    assert {:noreply, _} = SubformHelpers.sequenced_subform(socket, [1, 0])
    assert {:noreply, _} = SubformHelpers.remove_subentry(socket, "0")

    assert {:noreply, _} =
             SubformHelpers.append_subentries(
               socket,
               Changeset.change(%Var{type: :string, key: "n", label: "N", placement: :content})
             )
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

  describe "apply_op/2, applied by the form to its latest list" do
    # The form applies a subform's operation to its own changeset, which may
    # already hold an earlier click's result the subform has not seen yet.
    # Rows are named by key: a saved row's id, a new row's `_key`.

    defp row(key), do: %Var{key: key} |> Changeset.change() |> then(&%{&1 | params: %{"_key" => key}})
    defp keys(entries), do: Enum.map(entries, &SubformHelpers.row_key/1)

    test "adds are cumulative: a second add lands after the first" do
      entries = SubformHelpers.apply_op([row("a"), row("b")], {:append, [row("c")]})
      assert keys(SubformHelpers.apply_op(entries, {:append, [row("d")]})) == ~w(a b c d)
    end

    test "an insert goes above the named row, wherever it is by then" do
      # the editor clicked + above "b" while "a" was already being removed
      assert keys(SubformHelpers.apply_op([row("b"), row("c")], {:insert, "b", 1, row("x")})) == ~w(x b c)
      # a row without a key: at the position, past the end appending
      assert keys(SubformHelpers.apply_op([row("a"), row("b")], {:insert, nil, 1, row("x")})) == ~w(a x b)
      assert keys(SubformHelpers.apply_op([row("a")], {:insert, nil, 9, row("x")})) == ~w(a x)
    end

    test "a double click on × removes exactly one row" do
      once = SubformHelpers.apply_op([row("a"), row("b"), row("c")], {:delete, "a"})
      assert keys(once) == ~w(b c)
      # the second click names a row that is gone, not the one in its place
      assert SubformHelpers.apply_op(once, {:delete, "a"}) == :stale
    end

    test "an add and a removal queued together both apply" do
      added = SubformHelpers.apply_op([row("a"), row("b")], {:append, [row("c")]})
      assert keys(SubformHelpers.apply_op(added, {:delete, "a"})) == ~w(b c)
    end

    test "a reorder moves the named rows and keeps one added since" do
      entries = [row("a"), row("b"), row("c"), row("new")]
      assert keys(SubformHelpers.apply_op(entries, {:reorder, ~w(c a b), false})) == ~w(c a b new)
      assert keys(SubformHelpers.apply_op(entries, {:reorder, ~w(gone c), false})) == ~w(c a b new)
      assert SubformHelpers.apply_op(entries, {:reorder, ~w(gone), false}) == :stale
    end

    test "a reorder of a sequenced relation numbers the rows", %{pending: pending} do
      entries = SubformHelpers.current_entries(pending, :vars)
      [one, two] = keys(entries)
      reordered = SubformHelpers.apply_op(entries, {:reorder, [two, one], true})

      assert Enum.map(reordered, &Changeset.get_field(&1, :key)) == ["two", "one"]
      assert Enum.map(reordered, &Changeset.get_field(&1, :sequence)) == [0, 1]
      # the pending edit rides along
      assert Enum.at(reordered, 1).changes[:value] == "PENDING"
    end

    test "a replacement and a function both work on the latest list" do
      assert keys(SubformHelpers.apply_op([row("a"), row("b")], {:replace, "b", row("b2")})) == ~w(a b2)
      assert SubformHelpers.apply_op([row("a")], {:replace, "b", row("b2")}) == :stale
      assert keys(SubformHelpers.apply_op([row("a"), row("b")], {:update, &Enum.reverse/1})) == ~w(b a)
    end
  end

  describe "rows the editor removed" do
    # A saved row removed in the form (its × sets the drop param) stays in the
    # relation as a changeset marked for removal. Written back, it raised
    # "cannot replace related", so removing a saved row and then adding one
    # crashed the LiveView, and it shifted every position after it.
    setup %{block: block} do
      [one, two] = Enum.sort_by(block.vars, & &1.key)

      removed =
        block
        |> Changeset.change()
        |> Changeset.put_assoc(:vars, [Changeset.change(two)])

      assert Enum.any?(Changeset.get_assoc(removed, :vars), &(&1.action == :replace))
      %{removed: removed, one: one, two: two}
    end

    test "are not current entries", %{removed: removed, two: two} do
      assert SubformHelpers.row_keys(removed, :vars) == ["id-#{two.id}"]
    end

    test "an add after a removal is saved, and the removal too", %{removed: removed} do
      new = SubformHelpers.new_row(%Var{type: :string, key: "three", label: "Three", value: "new", placement: :content})

      updated =
        removed
        |> SubformHelpers.current_entries(:vars)
        |> SubformHelpers.apply_op({:append, [new]})
        |> then(&SubformHelpers.put_entries(removed, :vars, &1))

      assert persisted_values(updated) == %{"two" => "orig2", "three" => "new"}
    end

    test "two saved rows removed one after the other", %{block: block, one: one, two: two} do
      changeset = Changeset.change(block)

      updated =
        Enum.reduce(["id-#{one.id}", "id-#{two.id}"], changeset, fn key, changeset ->
          changeset
          |> SubformHelpers.current_entries(:vars)
          |> SubformHelpers.apply_op({:delete, key})
          |> then(&SubformHelpers.put_entries(changeset, :vars, &1))
        end)

      assert persisted_values(updated) == %{}
    end

    test "two new rows added one after the other are both saved", %{block: block} do
      var = fn key ->
        SubformHelpers.new_row(%Var{type: :string, key: key, label: key, value: key, placement: :content})
      end

      updated =
        Enum.reduce(["three", "four"], Changeset.change(block), fn key, changeset ->
          changeset
          |> SubformHelpers.current_entries(:vars)
          |> SubformHelpers.apply_op({:append, [var.(key)]})
          |> then(&SubformHelpers.put_entries(changeset, :vars, &1))
        end)

      assert persisted_values(updated) == %{"one" => "orig1", "two" => "orig2", "three" => "three", "four" => "four"}
    end
  end

  describe "PageVars and Globals" do
    # Both name a row to remove by its key and append through the form. Each
    # click is handled with the form as the component last rendered it; the
    # form then applies the operation it sends to its latest changeset, which
    # is what `apply_in_form/2` does here.
    alias BrandoAdmin.Components.Form.Input.Globals
    alias BrandoAdmin.Components.Pages.PageVars

    defp socket(changeset) do
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(:field, Phoenix.Component.to_form(changeset, as: "block")[:vars])
      |> Phoenix.Component.assign(:subform, %{name: :vars})
    end

    defp click(component, changeset, event, value) do
      {:noreply, _} = component.handle_event(event, value, socket(changeset))
      assert_received {:phoenix, :send_update, {{BrandoAdmin.Components.Form, _}, %{field: :vars, op: op}}}
      op
    end

    defp var_keys(changeset),
      do: changeset |> SubformHelpers.current_entries(:vars) |> Enum.map(&Changeset.get_field(&1, :key))

    defp apply_in_form(changeset, op) do
      case changeset |> SubformHelpers.current_entries(:vars) |> SubformHelpers.apply_op(op) do
        :stale -> changeset
        entries -> SubformHelpers.put_entries(changeset, :vars, entries)
      end
    end

    for component <- [PageVars, Globals] do
      test "#{inspect(component)}: two saved rows removed one after the other", %{block: block} do
        changeset = Changeset.change(block)
        [one, two] = SubformHelpers.row_keys(changeset, :vars)

        changeset = apply_in_form(changeset, click(unquote(component), changeset, "remove_subentry", %{"key" => one}))
        changeset = apply_in_form(changeset, click(unquote(component), changeset, "remove_subentry", %{"key" => two}))

        assert persisted_values(changeset) == %{}
      end

      test "#{inspect(component)}: a double click on × removes exactly one row", %{block: block} do
        changeset = Changeset.change(block)
        [one, _two] = SubformHelpers.row_keys(changeset, :vars)

        # both clicks are handled with the list as it was rendered
        first = click(unquote(component), changeset, "remove_subentry", %{"key" => one})
        second = click(unquote(component), changeset, "remove_subentry", %{"key" => one})

        assert changeset |> apply_in_form(first) |> apply_in_form(second) |> persisted_values() == %{"two" => "orig2"}
      end

      test "#{inspect(component)}: an add and a removal queued together both apply", %{block: block} do
        changeset = Changeset.change(block)
        [one, _two] = SubformHelpers.row_keys(changeset, :vars)

        add = click(unquote(component), changeset, "add_subentry", %{})
        remove = click(unquote(component), changeset, "remove_subentry", %{"key" => one})

        assert changeset |> apply_in_form(add) |> apply_in_form(remove) |> var_keys() == ["two", "key"]
      end

      test "#{inspect(component)}: an add after a saved row is removed", %{block: block} do
        changeset = Changeset.change(block)
        [one, _two] = SubformHelpers.row_keys(changeset, :vars)

        changeset = apply_in_form(changeset, click(unquote(component), changeset, "remove_subentry", %{"key" => one}))
        changeset = apply_in_form(changeset, click(unquote(component), changeset, "add_subentry", %{}))

        # the new variable is filled in and validated through the form; that
        # the removal and the new row go together is what crashed
        assert var_keys(changeset) == ["two", "key"]
        assert Enum.count(Changeset.get_assoc(changeset, :vars), &(&1.action == :replace)) == 1
      end
    end
  end
end
