defmodule Brando.ColorStoredValuesTest.Theme do
  @moduledoc false
  use Ecto.Schema

  schema "themes" do
    field :accent, :string
  end
end

defmodule Brando.ColorStoredValuesTest.Article do
  @moduledoc false
  # A Blueprint with a subform on a belongs_to, as `__color_fields__` gives it
  use Ecto.Schema

  schema "articles" do
    field :title, :string
    belongs_to :theme, Brando.ColorStoredValuesTest.Theme
  end

  def __color_fields__, do: [{:theme, [:accent]}]
end

defmodule Brando.ColorStoredValuesTest do
  # Colours stored before `Brando.Color` checked them: a module's colour var
  # default, a revision's colour. Copies and restores leave them empty rather
  # than refusing the save.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Color
  alias Brando.Content.Blocks
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Revisions

  @stored "red;background:url(x)"

  setup do
    {:ok, user: Factory.insert(:random_user)}
  end

  defp color_var(key, value, sequence \\ 0),
    do: %Var{type: :color, key: key, label: %{"en" => key}, value: value, sequence: sequence}

  # Stored as it was before the check: inserted without a changeset
  defp module_with_defaults do
    Factory.insert(:module,
      vars: [
        color_var("bg", @stored, 0),
        color_var("fg", "#112233", 1),
        %Var{type: :string, key: "text", label: %{"en" => "Text"}, value: @stored, sequence: 2}
      ]
    )
    |> Brando.Cache.Query.evict()
  end

  defp values(vars), do: Map.new(vars, &key_value/1)

  defp key_value(%{"key" => key} = var), do: {key, var["value"]}
  defp key_value(var), do: {var.key, var.value}

  describe "a module's colour var default that is not a colour" do
    test "a new block starts the var empty and saves", %{user: user} do
      module = module_with_defaults()

      block =
        module.id
        |> Blocks.build_module_block(user.id, nil, Page.Blocks, :module)
        |> Ecto.Changeset.apply_changes()

      assert values(block.vars) == %{"bg" => nil, "fg" => "#112233", "text" => @stored}

      # The block's vars come back from the editor as params, as the form sends them
      vars = Enum.map(block.vars, &Map.take(&1, [:type, :key, :label, :value, :sequence]))
      block_params = %{uid: block.uid, type: :module, module_id: module.id, source: Page.Blocks, vars: vars}
      params = Factory.params_for(:page, vars: [], entry_blocks: [%{sequence: 0, block: block_params}])

      assert {:ok, page} = %Page{} |> Page.changeset(params, user, nil, cast_blocks: true) |> Brando.Repo.insert()

      stored =
        Brando.Repo.all(
          from(v in Var,
            join: b in assoc(v, :block),
            join: j in Page.Blocks,
            on: j.block_id == b.id,
            where: j.entry_id == ^page.id
          )
        )

      assert values(stored) == %{"bg" => nil, "fg" => "#112233", "text" => @stored}
    end

    test "restoring a recovery copy adds the missing var empty" do
      module = module_with_defaults()
      fields = %{"blocks" => [%{"uid" => "draft-block", "module_id" => module.id, "refs" => [], "vars" => []}]}

      assert {%{"blocks" => [recovered]}, []} =
               Brando.Drafts.Modules.check(fields, Brando.Drafts.Modules.manifest(fields))

      assert values(recovered["vars"]) == %{"bg" => nil, "fg" => "#112233", "text" => @stored}
    end

    test "an imported block missing the var gets it empty" do
      module = module_with_defaults()
      params = Brando.Content.Transfer.Contracts.defaults(%{"refs" => [], "vars" => []}, module)

      assert values(params["vars"]) == %{"bg" => nil, "fg" => "#112233", "text" => @stored}
    end

    test "the module still saves; a changed default must be a colour", %{user: user} do
      module = Brando.Repo.preload(module_with_defaults(), :vars)

      var_params = fn bg ->
        Enum.map(module.vars, &%{id: &1.id, key: &1.key, value: if(&1.key == "bg", do: bg, else: &1.value)})
      end

      assert {:ok, _} = Brando.Content.update_module(module, %{help_text: "Edited"}, user)
      assert {:ok, _} = Brando.Content.update_module(module, %{vars: var_params.(@stored)}, user)
      assert {:error, changeset} = Brando.Content.update_module(module, %{vars: var_params.("blue;x")}, user)
      assert Enum.any?(changeset.changes.vars, &(&1.errors[:value] != nil))
    end
  end

  describe "restoring a revision with a colour that is not a colour" do
    test "restores it empty instead of refusing", %{user: user} do
      {:ok, page} =
        Pages.create_page(
          Factory.params_for(:page, vars: [%{type: :color, key: "bg", label: %{"en" => "Bg"}, value: "#000000"}]),
          user
        )

      page = Brando.Repo.preload(page, :vars)
      [var] = page.vars
      # The revision was taken before values were checked
      {:ok, revision} =
        Revisions.create_revision(%{page | title: "Older", vars: [%{var | value: @stored}]}, user, false)

      assert {:ok, _} = Revisions.set_entry_to_revision(Page, page.id, revision.revision, user)

      restored = Page |> Brando.Repo.get!(page.id) |> Brando.Repo.preload(:vars)
      assert restored.title == "Older"
      assert [%{key: "bg", value: nil}] = restored.vars
    end
  end

  describe "clear_invalid/1" do
    test "empties colour fields and colour vars at any depth, and says which" do
      palette = %Brando.Content.Palette{
        key: "site",
        colors: [
          %Brando.Content.Palette.Color{key: "ink", hex_value: @stored},
          %Brando.Content.Palette.Color{key: "paper", hex_value: "#fff"}
        ]
      }

      block = %Brando.Content.Block{
        vars: [color_var("bg", @stored), color_var("fg", "#000")],
        children: [%Brando.Content.Block{vars: [color_var("deep", "url(x)")], children: []}]
      }

      page = %Page{title: "Page", entry_blocks: [%Page.Blocks{block: block}], vars: []}

      assert {%{colors: [%{hex_value: nil}, %{hex_value: "#fff"}]}, [_]} = Color.clear_invalid(palette)

      assert {cleared_page, cleared} = Color.clear_invalid(page)
      assert length(cleared) == 2
      [%{block: %{vars: [bg, fg], children: [%{vars: [deep]}]}}] = cleared_page.entry_blocks
      assert {bg.value, fg.value, deep.value} == {nil, "#000", nil}

      # A ref's image is not the entry's content: its colour is left as it is
      ref = %Brando.Content.Ref{image: %Brando.Images.Image{dominant_color: @stored}}

      assert {%{refs: [%{image: %{dominant_color: @stored}}]}, []} =
               Color.clear_invalid(%Brando.Content.Block{refs: [ref]})

      assert Color.clear_invalid(%Brando.Images.Image{dominant_color: "#abc"}) |> elem(1) == []
    end

    test "clears a subform on a belongs_to" do
      alias Brando.ColorStoredValuesTest.{Article, Theme}

      assert {%Article{theme: %Theme{accent: nil}}, [_]} =
               Color.clear_invalid(%Article{theme: %Theme{accent: @stored}})
    end

    test "leaves what a record refers to, and relations its snapshot lacks, as they are" do
      palette = %Brando.Content.Palette{colors: [%Brando.Content.Palette.Color{key: "ink", hex_value: @stored}]}
      module = %Brando.Content.Module{vars: [color_var("bg", @stored)]}
      block = %Brando.Content.Block{palette: palette, module: module, vars: [color_var("fg", "#000")]}

      assert Color.clear_invalid(block) == {block, []}

      # A revision taken before a relation was added has no key for it
      old_snapshot = Map.delete(%Page{title: "Old", vars: [color_var("bg", @stored)]}, :entry_blocks)
      {restored, [_]} = Color.clear_invalid(old_snapshot)
      refute Map.has_key?(restored, :entry_blocks)
      assert [%{value: nil}] = restored.vars
      assert {%{dominant_color: nil}, [_]} = Color.clear_invalid(%Brando.Images.Image{dominant_color: @stored})
    end
  end
end
