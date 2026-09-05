defmodule Brando.Drafts.RestoreTest do
  use Brando.ConnCase, async: false
  alias Brando.Drafts
  alias Brando.Drafts.Modules
  alias Brando.Drafts.Params
  alias Brando.Drafts.Restore
  alias Brando.Factory
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)
    {:ok, page} = Brando.Blueprint.EntryQuery.get(Brando.Pages.Page, page.id)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, vars: [%{key: "heading", label: "Heading", type: :string, value: "Default"}]),
        user
      )

    blocks = %{
      "blocks" => [
        %{
          "block" => %{
            "type" => "module",
            "uid" => Brando.Utils.generate_uid(),
            "module_id" => module.id,
            "module_origin" => "local",
            "vars" => [%{"key" => "heading", "type" => "string", "value" => "Recovered heading"}],
            "refs" => [],
            "children" => []
          }
        }
      ]
    }

    draft = %{
      format_version: 1,
      schema_version: Brando.Blueprint.Snapshot.get_current_version(Brando.Pages.Page),
      base_fingerprint: Drafts.fingerprint(page),
      payload: %{"main" => %{"title" => "Recovered title"}, "blocks" => blocks, "modules" => Modules.manifest(blocks)}
    }

    {:ok, user: user, page: page, module: module, draft: draft}
  end

  test "restores a new block and entry values without updating the saved entry", ctx do
    assert {:ok, cs, []} = Restore.prepare(ctx.draft, ctx.page, Brando.Pages.Page, ctx.user)
    assert Changeset.get_field(cs, :title) == "Recovered title"
    assert [join] = Changeset.get_assoc(cs, :entry_blocks)
    [var] = join |> Changeset.get_assoc(:block) |> Changeset.get_assoc(:vars)
    assert Changeset.get_field(var, :value) == "Recovered heading"
    assert Brando.Repo.get!(Brando.Pages.Page, ctx.page.id).title == ctx.page.title
  end

  test "added variables get defaults without changing existing draft values", ctx do
    {:ok, _} =
      Brando.Content.update_module(
        ctx.module,
        %{
          vars: [
            %{id: hd(ctx.module.vars).id, key: "heading", label: "Heading", type: :string},
            %{key: "caption", label: "Caption", type: :string, value: "New caption"}
          ]
        },
        ctx.user
      )

    assert {:ok, cs, []} = Restore.prepare(ctx.draft, ctx.page, Brando.Pages.Page, ctx.user)
    [join] = Changeset.get_assoc(cs, :entry_blocks)

    vars =
      join
      |> Changeset.get_assoc(:block)
      |> Changeset.get_assoc(:vars)
      |> Map.new(&{Changeset.get_field(&1, :key), Changeset.get_field(&1, :value)})

    assert vars == %{"heading" => "Recovered heading", "caption" => "New caption"}
  end

  test "removed or retyped variables require review and compatible-only recovery retains the payload", ctx do
    {:ok, _} = Brando.Content.update_module(ctx.module, %{vars: []}, ctx.user)
    assert {:review, :modules_changed, [_]} = Restore.prepare(ctx.draft, ctx.page, Brando.Pages.Page, ctx.user)
    assert {:ok, cs, [_]} = Restore.prepare(ctx.draft, ctx.page, Brando.Pages.Page, ctx.user, compatible_only: true)
    assert Changeset.get_assoc(cs, :entry_blocks) == []
    assert Changeset.get_field(cs, :title) == "Recovered title"
    assert get_in(ctx.draft.payload, ["blocks", "blocks"]) != []
  end

  test "a changed saved entry requires explicit confirmation", ctx do
    changed = %{ctx.page | updated_at: NaiveDateTime.add(ctx.page.updated_at, 10, :second)}
    assert {:review, :entry_changed, []} = Restore.prepare(ctx.draft, changed, Brando.Pages.Page, ctx.user)
    assert {:ok, _, []} = Restore.prepare(ctx.draft, changed, Brando.Pages.Page, ctx.user, accept_conflict: true)

    assert {:review, :entry_changed, []} =
             Restore.prepare(ctx.draft, %{ctx.page | title: "Changed in the same second"}, Brando.Pages.Page, ctx.user)
  end

  test "unsupported payloads fail without modifying the entry", ctx do
    assert {:error, _} = Restore.prepare(%{ctx.draft | format_version: 99}, ctx.page, Brando.Pages.Page, ctx.user)
    assert Brando.Repo.get!(Brando.Pages.Page, ctx.page.id).title == ctx.page.title
  end

  test "keeps invalid scalar and nested values in snapshots" do
    cs = Changeset.cast({%{number: 1}, %{number: :integer}}, %{"number" => "half typed"}, [:number])
    assert Params.snapshot(cs)["number"] == "half typed"
    assert BrandoAdmin.Components.Form.BlockField.Ops.changes_to_params(cs)["number"] == "half typed"
  end

  test "snapshot keeps a selected asset as a library reference" do
    image = Factory.insert(:image)
    cs = %Brando.Content.Ref{image: nil} |> Changeset.change() |> Changeset.put_assoc(:image, image)
    params = Params.snapshot(cs)
    assert params["image_id"] == image.id
    refute Map.has_key?(params, "image")
  end

  test "visible partial fields cannot remove other refs or structural children" do
    block = %{
      "uid" => "root",
      "refs" => [%{"name" => "one", "value" => "old"}, %{"name" => "two", "value" => "retained"}],
      "children" => [%{"uid" => "child", "vars" => []}]
    }

    forms = %{"root" => %{"block" => %{"refs" => %{"0" => %{"value" => "new"}}, "children" => []}}}
    result = Params.overlay_block(block, forms)
    assert Enum.map(result["refs"], & &1["value"]) == ["new", "retained"]
    assert [%{"uid" => "child"}] = result["children"]
  end

  test "new nested snapshots retain seeded fields and invalid values" do
    child = %Brando.Content.Block{uid: "nested", module_id: 41, sequence: 0}
    nested = Changeset.cast(child, %{"sequence" => "unfinished"}, [:sequence])

    cs =
      %Brando.Content.Block{uid: "root", children: [child]}
      |> Changeset.change()
      |> Changeset.put_assoc(:children, [nested])

    snapshot = BrandoAdmin.Components.Form.BlockField.Ops.snapshot_params(cs)
    assert [%{"uid" => "nested", "module_id" => 41, "sequence" => "unfinished"}] = snapshot["children"]
  end
end
