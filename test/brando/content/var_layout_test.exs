defmodule Brando.Content.VarLayoutTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Var
  alias Brando.Content.Var.Layout

  doctest Brando.Content.Var.Layout

  defp var(key, attrs) do
    Enum.into(attrs, %{key: key, width: :full, new_row: false, placement: :content, sequence: 0})
  end

  defp keys(rows), do: Enum.map(rows, fn row -> Enum.map(row, & &1.key) end)

  describe "unit_cost/1" do
    test "fixed widths claim their share of twelve" do
      assert Layout.unit_cost(:full) == 12
      assert Layout.unit_cost(:half) == 6
      assert Layout.unit_cost(:third) == 4
      assert Layout.unit_cost(:fourth) == 3
    end

    test "flexible widths reserve a floor rather than a measure" do
      assert Layout.unit_cost(:auto) == 2
      assert Layout.unit_cost(:fill) == 2
    end

    test "accepts strings coming off a form" do
      assert Layout.unit_cost("half") == 6
    end

    test "an unknown width falls back to a whole row rather than crashing" do
      assert Layout.unit_cost("nonsense-width") == 12
    end
  end

  describe "pack/1" do
    test "fills a row up to twelve units before breaking" do
      rows =
        Layout.pack([
          var("a", width: :third),
          var("b", width: :third),
          var("c", width: :third),
          var("d", width: :third)
        ])

      assert keys(rows) == [["a", "b", "c"], ["d"]]
    end

    test "new_row breaks even when the row has room" do
      rows = Layout.pack([var("a", width: :half), var("b", width: :half, new_row: true)])

      assert keys(rows) == [["a"], ["b"]]
    end

    test "never puts more than four vars on a row" do
      rows =
        Layout.pack([
          var("a", width: :auto),
          var("b", width: :auto),
          var("c", width: :auto),
          var("d", width: :auto),
          var("e", width: :auto)
        ])

      assert keys(rows) == [["a", "b", "c", "d"], ["e"]]
    end

    test "a full-width var always lands alone" do
      rows = Layout.pack([var("a", width: :half), var("b", width: :full), var("c", width: :half)])

      assert keys(rows) == [["a"], ["b"], ["c"]]
    end

    test "flexible slots share a row with fixed ones" do
      rows =
        Layout.pack([
          var("a", width: :auto),
          var("b", width: :fill),
          var("c", width: :auto)
        ])

      assert keys(rows) == [["a", "b", "c"]]
    end

    test "an empty list packs to no rows" do
      assert Layout.pack([]) == []
    end
  end

  describe "pack_placement/2" do
    test "keeps only the requested surface and sorts by sequence" do
      vars = [
        var("c", placement: :content, sequence: 2),
        var("hidden", placement: :hidden, sequence: 3),
        var("a", placement: :content, sequence: 0),
        var("cfg", placement: :config, sequence: 1)
      ]

      assert keys(Layout.pack_placement(vars, :content)) == [["a"], ["c"]]
      assert keys(Layout.pack_placement(vars, :config)) == [["cfg"]]
      assert keys(Layout.pack_placement(vars, :hidden)) == [["hidden"]]
    end
  end

  describe "fits?/2" do
    test "rejects on the unit budget" do
      refute Layout.fits?([var("a", width: :half)], :full)
      assert Layout.fits?([var("a", width: :half)], :half)
    end

    test "rejects on the slot count even when units allow it" do
      row = for key <- ~w(a b c d), do: var(key, width: :auto)

      refute Layout.fits?(row, :auto)
    end
  end

  describe "flatten/1" do
    test "derives sequence and new_row from the row structure" do
      attrs = Layout.flatten(%{content: [["a", "b"], ["c"]]})

      assert attrs["a"] == %{sequence: 0, new_row: true, placement: :content}
      assert attrs["b"] == %{sequence: 1, new_row: false, placement: :content}
      assert attrs["c"] == %{sequence: 2, new_row: true, placement: :content}
    end

    test "numbers surfaces continuously so sequence stays globally unique" do
      attrs = Layout.flatten(%{content: [["a"]], config: [["b"]], hidden: [["c"]]})

      assert Enum.sort(Enum.map(attrs, fn {_k, v} -> v.sequence end)) == [0, 1, 2]
      assert attrs["b"].placement == :config
      assert attrs["c"].placement == :hidden
    end

    test "round-trips through pack/1" do
      rows = %{content: [["a", "b"], ["c", "d"]]}

      vars =
        rows
        |> Layout.flatten()
        |> Enum.map(fn {key, attrs} -> var(key, Enum.to_list(attrs) ++ [width: :half]) end)
        |> Enum.sort_by(& &1.sequence)

      assert keys(Layout.pack(vars)) == [["a", "b"], ["c", "d"]]
    end
  end

  describe "merge_surface/3" do
    setup do
      vars = [
        var("a", placement: :content, sequence: 0),
        var("b", placement: :content, sequence: 1),
        var("cfg", placement: :config, sequence: 2),
        var("secret", placement: :hidden, sequence: 3)
      ]

      %{vars: vars}
    end

    test "applies the reported rows to the edited surface", %{vars: vars} do
      attrs = Layout.merge_surface(vars, :content, [["b", "a"]])

      assert attrs["b"].sequence < attrs["a"].sequence
      assert attrs["b"].new_row == true
      assert attrs["a"].new_row == false
    end

    test "leaves untouched surfaces on their own placement", %{vars: vars} do
      attrs = Layout.merge_surface(vars, :content, [["a"], ["b"]])

      assert attrs["cfg"].placement == :config
      assert attrs["secret"].placement == :hidden
    end

    test "keeps sequence a single continuous ordering across surfaces", %{vars: vars} do
      attrs = Layout.merge_surface(vars, :content, [["a", "b"]])
      sequences = attrs |> Enum.map(fn {_key, value} -> value.sequence end) |> Enum.sort()

      assert sequences == [0, 1, 2, 3]
    end

    test "ignores keys the var list does not know", %{vars: vars} do
      attrs = Layout.merge_surface(vars, :content, [["a", "ghost"], ["b"]])

      refute Map.has_key?(attrs, "ghost")
      assert Map.has_key?(attrs, "a")
      assert attrs["b"].new_row == true
    end

    # A var the payload never mentions is left alone rather than reassigned,
    # so a DOM that lost a chip cannot orphan or silently move a variable.
    test "a var missing from the payload keeps whatever it had", %{vars: vars} do
      attrs = Layout.merge_surface(vars, :config, [])

      refute Map.has_key?(attrs, "cfg")
      assert attrs["a"].placement == :content
      assert attrs["secret"].placement == :hidden
    end
  end

  describe "normalize_payload/1" do
    test "converts the JS payload and drops unknown surfaces" do
      payload = %{"content" => [["a", "b"]], "bogus" => [["x"]]}

      assert Layout.normalize_payload(payload) == %{
               content: [["a", "b"]],
               config: [],
               hidden: []
             }
    end

    test "drops empty rows and non-string entries" do
      payload = %{"content" => [[], ["a", 42]]}

      assert Layout.normalize_payload(payload).content == [["a"]]
    end
  end

  describe "apply_layout/2" do
    test "updates structs it knows about and leaves the rest alone" do
      vars = [
        %Var{key: "a", sequence: 9, new_row: false, placement: :config},
        %Var{key: "untouched", sequence: 3, placement: :hidden}
      ]

      [a, untouched] = Layout.apply_layout(vars, Layout.flatten(%{content: [["a"]]}))

      assert a.sequence == 0
      assert a.new_row == true
      assert a.placement == :content

      assert untouched.sequence == 3
      assert untouched.placement == :hidden
    end

    test "works on changesets" do
      changeset = Ecto.Changeset.change(%Var{key: "a"})

      [applied] = Layout.apply_layout([changeset], Layout.flatten(%{config: [["a"]]}))

      assert Ecto.Changeset.get_field(applied, :placement) == :config
      assert Ecto.Changeset.get_field(applied, :new_row) == true
    end
  end

  describe "default_width/1" do
    test "booleans start narrow so several stack on a row" do
      assert Layout.default_width(:boolean) == :fourth
    end

    test "short pickers start at a third" do
      assert Layout.default_width(:select) == :third
      assert Layout.default_width(:color) == :third
    end

    test "everything else claims a row" do
      assert Layout.default_width(:string) == :full
      assert Layout.default_width(:image) == :full
    end
  end
end
