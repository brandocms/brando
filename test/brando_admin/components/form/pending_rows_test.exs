defmodule BrandoAdmin.Components.Form.PendingRowsTest do
  # A change serialized before an add or a removal reached the browser lists
  # the rows as they were (#3157). `PendingRows` corrects only that, before
  # Ecto casts the params as usual.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Var
  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias BrandoAdmin.Components.Form.PendingRows
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    entry_block =
      %Brando.Pages.Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "pendingrows",
        type: :module,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        vars: [
          %{type: :string, key: "a", label: "A", value: "a", placement: :content, width: :full, sequence: 0},
          %{type: :string, key: "b", label: "B", value: "b", placement: :content, width: :full, sequence: 1},
          %{type: :string, key: "c", label: "C", value: "c", placement: :content, width: :full, sequence: 2}
        ]
      })
      |> Brando.Repo.insert!()
      |> Brando.Repo.preload(block: [:vars, :creator])

    block = entry_block.block
    [a, b, c] = Enum.sort_by(block.vars, & &1.key)
    {:ok, block: block, a: a, b: b, c: c, user: user}
  end

  # The browser's params for `rows` ({var, value}), in that order, as the
  # subform renders them: each row by index, with a sort entry each.
  defp params(rows, extra \\ %{}) do
    indexed = Enum.with_index(rows)

    Map.merge(
      %{
        "vars" => Map.new(indexed, fn {{var, value}, i} -> {to_string(i), row(var, value)} end),
        "sort_var_ids" => Enum.map(indexed, fn {_, i} -> to_string(i) end)
      },
      extra
    )
  end

  defp row(%Var{id: id}, value) when not is_nil(id), do: %{"id" => to_string(id), "value" => value}
  defp row(%{"_key" => _} = new, value), do: Map.put(new, "value", value)

  defp cast(block, params, user), do: Brando.Content.Block.changeset(block, params, user)

  defp current(block, rows), do: SubformHelpers.put_entries(Changeset.change(block), :vars, rows)

  defp values(changeset) do
    changeset |> SubformHelpers.current_entries(:vars) |> Enum.map(&Changeset.get_field(&1, :key))
  end

  defp new_var(key) do
    SubformHelpers.new_row(%Var{type: :string, key: key, label: String.upcase(key), value: key, placement: :content})
  end

  test "nothing pending leaves the params as they are", %{block: block, a: a, b: b, c: c} do
    params = params([{c, "c"}, {a, "a"}, {b, "b"}])
    assert {^params, _} = PendingRows.correct(params, %{}, current(block, [a, b, c]))
  end

  test "a row removed since is taken out, with its sort and drop entries", %{block: block, a: a, b: b, c: c} do
    server = current(block, [Changeset.change(a), Changeset.change(c)])
    pending = PendingRows.record(%{}, :vars, ["id-#{a.id}", "id-#{b.id}", "id-#{c.id}"], ["id-#{a.id}", "id-#{c.id}"])

    # Serialized before the patch: b still listed, c typed into
    stale = params([{a, "a"}, {b, "b"}, {c, "C2"}], %{"drop_var_ids" => [""]})
    {corrected, listed} = PendingRows.correct(stale, pending, server)

    refute Map.has_key?(corrected["vars"], "1")
    assert corrected["sort_var_ids"] == ["0", "2"]
    changeset = cast(block, corrected, block.creator)
    assert values(changeset) == ["a", "c"]
    assert changeset |> SubformHelpers.current_entries(:vars) |> List.last() |> Changeset.get_field(:value) == "C2"

    # Until the browser stops listing b, b stays removed
    pending = PendingRows.settle(pending, listed, changeset)
    assert MapSet.member?(pending.vars.removed, "id-#{b.id}")
    {_, listed} = PendingRows.correct(params([{a, "a"}, {c, "C2"}]), pending, server)
    assert PendingRows.settle(pending, listed, changeset) == %{}
  end

  test "a row added since is put in where the server placed it, and validated", %{block: block, a: a, b: b} do
    added = new_var("n")
    server = current(block, [Changeset.change(a), added, Changeset.change(b)])

    pending =
      PendingRows.record(%{}, :vars, ["id-#{a.id}", "id-#{b.id}"], [
        "id-#{a.id}",
        SubformHelpers.row_key(added),
        "id-#{b.id}"
      ])

    stale = params([{a, "typed"}, {b, "b"}])
    {corrected, listed} = PendingRows.correct(stale, pending, server)

    changeset = cast(block, corrected, block.creator)
    assert values(changeset) == ["a", "n", "b"]
    assert changeset |> SubformHelpers.current_entries(:vars) |> hd() |> Changeset.get_field(:value) == "typed"
    assert SubformHelpers.row_keys(changeset, :vars) |> Enum.at(1) == SubformHelpers.row_key(added)

    # Listed by the next change: settled
    pending = PendingRows.settle(pending, listed, changeset)
    assert MapSet.member?(pending.vars.added, SubformHelpers.row_key(added))
    caught_up = params([{a, "a"}, {%{"_key" => SubformHelpers.row_key(added)}, "n"}, {b, "b"}])
    {_, listed} = PendingRows.correct(caught_up, pending, server)
    assert PendingRows.settle(pending, listed, changeset) == %{}
  end

  test "an added row the change never drew is validated like any other", %{block: block, a: a} do
    # A row added without its required key: Ecto must still see and refuse it
    added = SubformHelpers.new_row(%Var{type: :string, label: "Empty", placement: :content})
    server = current(block, [Changeset.change(a), added])
    pending = PendingRows.record(%{}, :vars, ["id-#{a.id}"], ["id-#{a.id}", SubformHelpers.row_key(added)])

    {corrected, _} = PendingRows.correct(params([{a, "a"}]), pending, server)
    refute cast(block, corrected, block.creator).valid?
  end

  test "a drag's order and the browser's own drop param are Ecto's", %{block: block, a: a, b: b, c: c} do
    server = current(block, [a, b, c])
    # Dragged c to the top, and removed a with its × (drop param)
    dragged = params([{c, "c"}, {a, "a"}, {b, "b"}], %{"drop_var_ids" => ["1"]})
    {corrected, listed} = PendingRows.correct(dragged, %{}, server)
    changeset = cast(block, corrected, block.creator)
    assert values(changeset) == ["c", "b"]

    # The removal is remembered: a change still listing a (sent before the
    # patch) does not bring it back
    pending = PendingRows.settle(%{}, listed, changeset)
    assert MapSet.member?(pending.vars.removed, "id-#{a.id}")
    {corrected, _} = PendingRows.correct(params([{c, "c"}, {a, "a"}, {b, "b"}]), pending, current(block, [c, b]))
    assert values(cast(block, corrected, block.creator)) == ["c", "b"]
  end

  test "an added row is put in with its nested values" do
    # A new menu item comes with a required default link (Menu.default_item/2)
    item = SubformHelpers.new_row(Brando.Navigation.Menu.default_item(nil, nil))
    key = SubformHelpers.row_key(item)
    server = SubformHelpers.put_entries(Changeset.change(%Brando.Navigation.Menu{items: []}), :items, [item])
    pending = PendingRows.record(%{}, :items, [], [key])

    # The browser drew no rows yet: it sends the empty subform marker
    {corrected, _} = PendingRows.correct(%{"title" => "Main", "items" => ""}, pending, server)
    {_index, row} = corrected |> Map.fetch!("items") |> Enum.find(fn {_, row} -> row["_key"] == key end)
    assert %{"link_text" => "Text", "value" => "https://example.com", "type" => :link} = row["link"]
  end

  test "a row added last stays last in a list sent without a sort param", %{block: block, a: a, b: b} do
    added = new_var("n")
    server = current(block, [Changeset.change(a), Changeset.change(b), added])

    pending =
      PendingRows.record(%{}, :vars, ["id-#{a.id}", "id-#{b.id}"], [
        "id-#{a.id}",
        "id-#{b.id}",
        SubformHelpers.row_key(added)
      ])

    unsorted = params([{a, "a"}, {b, "b"}]) |> Map.delete("sort_var_ids")
    {corrected, _} = PendingRows.correct(unsorted, pending, server)

    assert values(cast(block, corrected, block.creator)) == ["a", "b", "n"]
  end
end
