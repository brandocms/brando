defmodule Brando.Content.ConditionalRefsTest do
  # B5 verification — are refs inside `{% if %}` / `{% for %}` regions deleted
  # on the first keystroke?
  #
  # `liquid_strip_logic/1` (block.ex) removes those regions from the module code
  # before the editor splits it into ref slots, so no inputs render for a ref
  # that lives inside one. `refs` is `on_replace: :delete_if_exists`, so the
  # question is what `cast_assoc(:refs)` does when params list a subset.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Content.Block
  alias Brando.Factory
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    entry_block =
      %Brando.Pages.Page.Blocks{}
      |> Changeset.change(%{entry_id: page.id, sequence: 0})
      |> Changeset.put_assoc(:block, %{
        uid: "condblock1",
        type: :module,
        active: true,
        source: "Elixir.Brando.Pages.Page.Blocks",
        creator_id: user.id,
        sequence: 0,
        refs: [
          %{name: "visible", uid: "refvisible", description: "outside the logic", sequence: 0},
          %{name: "conditional", uid: "refcondtnl", description: "inside {% if %}", sequence: 1}
        ]
      })
      |> Brando.Repo.insert!()
      |> Brando.Repo.preload(block: [:refs, :vars, :table_rows, :block_identifiers, :children])

    {:ok, user: user, block: entry_block.block}
  end

  defp ref_by_name(block, name), do: Enum.find(block.refs, &(&1.name == name))

  defp cast_with(block, user, refs_params) do
    params =
      %{"description" => "a keystroke"}
      |> then(fn p -> if refs_params, do: Map.put(p, "refs", refs_params), else: p end)

    Block.block_changeset(block, params, user.id)
  end

  test "params omitting the refs key entirely leave all refs alone", %{block: block, user: user} do
    changeset = cast_with(block, user, nil)

    # `cast/3` skips absent keys, so `cast_assoc(:refs)` never runs
    refute Map.has_key?(changeset.changes, :refs)
    assert length(Changeset.apply_changes(changeset).refs) == 2
  end

  test "params listing ONLY the rendered ref delete the unrendered one", %{block: block, user: user} do
    visible = ref_by_name(block, "visible")
    conditional = ref_by_name(block, "conditional")

    changeset =
      cast_with(block, user, %{
        "0" => %{"id" => to_string(visible.id), "name" => "visible"}
      })

    ref_changesets = Changeset.get_change(changeset, :refs, [])

    replaced =
      Enum.filter(ref_changesets, &(&1.action in [:replace, :delete]))
      |> Enum.map(& &1.data.id)

    assert conditional.id in replaced,
           "expected the unrendered ref to be marked for deletion — B5 confirmed"

    # and it really is gone once applied
    surviving = changeset |> Changeset.apply_changes() |> Map.get(:refs) |> Enum.map(& &1.name)
    assert surviving == ["visible"]
  end

  test "carrying the unrendered ref's identity keeps it", %{block: block, user: user} do
    visible = ref_by_name(block, "visible")
    conditional = ref_by_name(block, "conditional")

    changeset =
      cast_with(block, user, %{
        "0" => %{"id" => to_string(visible.id), "name" => "visible"},
        "1" => %{"id" => to_string(conditional.id)}
      })

    surviving =
      changeset |> Changeset.apply_changes() |> Map.get(:refs) |> Enum.map(& &1.name) |> Enum.sort()

    assert surviving == ["conditional", "visible"]

    # identity-only params must not blank the rest of the row
    kept =
      changeset |> Changeset.apply_changes() |> Map.get(:refs) |> Enum.find(&(&1.name == "conditional"))

    assert kept.description == "inside {% if %}"
    assert kept.uid == "refcondtnl"
  end

  describe "carried_refs/1" do
    test "emits identity for a ref the module code doesn't render", %{block: block} do
      html = render_carried(block, [{:ref, "visible"}, {:content, "some markup"}])

      # "conditional" is index 1 in the refs list
      assert html =~ ~s(name="block[refs][1][id]")
      assert html =~ ~s(name="block[refs][1][_persistent_id]")

      # the rendered one is left to `ref/1` — carrying it here would duplicate inputs
      refute html =~ ~s(name="block[refs][0][id]")
    end

    test "emits nothing when every ref is rendered", %{block: block} do
      html = render_carried(block, [{:ref, "visible"}, {:ref, "conditional"}])

      refute html =~ ~s(name="block[refs][0][id]")
      refute html =~ ~s(name="block[refs][1][id]")
    end

    test "does not carry an unsaved ref — identity-only would blank it", %{block: block} do
      # an unsaved ref appended by e.g. fetch_missing_refs
      changeset =
        Changeset.put_assoc(
          Changeset.change(block),
          :refs,
          Enum.map(block.refs, &Changeset.change/1) ++
            [Changeset.change(%Brando.Content.Ref{name: "fresh", uid: "reffresh01"})]
        )

      html = render_carried_cs(changeset, [{:ref, "visible"}, {:ref, "conditional"}])

      refute html =~ ~s(name="block[refs][2][id]")
    end

    defp render_carried(block, splits), do: render_carried_cs(Changeset.change(block), splits)

    defp render_carried_cs(changeset, splits) do
      render_component(
        &BrandoAdmin.Components.Form.Block.Render.carried_refs/1,
        refs_field: Phoenix.Component.to_form(changeset, as: "block")[:refs],
        liquid_splits: splits
      )
    end
  end
end
