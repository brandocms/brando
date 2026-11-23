defmodule Brando.Drafts.RestoreTest do
  use Brando.ConnCase, async: true
  alias Brando.Drafts
  alias Brando.Drafts.Modules
  alias Brando.Drafts.Params
  alias Brando.Drafts.Restore
  alias Brando.Factory
  alias Brando.Repo
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

  # A module set's picks are rows whose `module_id` is the module picked,
  # not an owner the server sets as it is in the block tree.
  test "restores a module set's picks", ctx do
    alias Brando.Content.ModuleSet

    set = Brando.Repo.insert!(%ModuleSet{title: "Set", creator_id: ctx.user.id})
    {:ok, set} = Brando.Blueprint.EntryQuery.get(ModuleSet, set.id)

    draft = %{
      format_version: 1,
      schema_version: Brando.Blueprint.Snapshot.get_current_version(ModuleSet),
      base_fingerprint: Drafts.fingerprint(set),
      payload: %{
        "main" => %{
          "title" => "Set",
          "module_set_modules" => [%{"id" => nil, "module_id" => ctx.module.id, "module_set_id" => nil, "sequence" => 0}]
        },
        "blocks" => %{}
      }
    }

    assert {:ok, cs, []} = Restore.prepare(draft, set, ModuleSet, ctx.user)
    assert [row] = Changeset.get_assoc(cs, :module_set_modules)
    assert Changeset.get_field(row, :module_id) == ctx.module.id
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

  # The Legacy Content Wrapper's `content` is a text ref that holds each
  # wrapped block as the type it was (`Brando.Content.Module.any_ref_type?/2`)
  test "a new Legacy Content Wrapper block keeps its wrapped content", ctx do
    {:ok, wrapper} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          class: Brando.Content.Module.legacy_wrapper_class(),
          code: "{% ref refs.content %}",
          refs: [%{name: "content", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: ""}}}]
        ),
        ctx.user
      )

    comment = %{"type" => "comment", "data" => %{"text" => "Bytt bilde i mai"}}

    blocks = %{
      "blocks" => [
        %{
          "block" => %{
            "type" => "module",
            "uid" => Brando.Utils.generate_uid(),
            "module_id" => wrapper.id,
            "module_origin" => "local",
            "refs" => [%{"uid" => Brando.Utils.generate_uid(), "name" => "content", "data" => comment}],
            "vars" => [],
            "children" => []
          }
        }
      ]
    }

    draft = %{ctx.draft | payload: %{"main" => %{}, "blocks" => blocks, "modules" => Modules.manifest(blocks)}}

    assert {:ok, cs, []} = Restore.prepare(draft, ctx.page, Brando.Pages.Page, ctx.user)
    [join] = Changeset.get_assoc(cs, :entry_blocks)
    [ref] = join |> Changeset.get_assoc(:block) |> Changeset.get_assoc(:refs)

    assert %Brando.Villain.Blocks.CommentBlock{data: %{text: "Bytt bilde i mai"}} =
             ref |> Changeset.apply_changes() |> Map.get(:data)
  end

  test "a Legacy Content Wrapper block whose `content` the wrapper no longer defines requires review", ctx do
    {:ok, wrapper} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          class: Brando.Content.Module.legacy_wrapper_class(),
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: ""}}}]
        ),
        ctx.user
      )

    blocks = %{
      "blocks" => [
        %{
          "block" => %{
            "type" => "module",
            "uid" => Brando.Utils.generate_uid(),
            "module_id" => wrapper.id,
            "module_origin" => "local",
            "refs" => [
              %{
                "uid" => Brando.Utils.generate_uid(),
                "name" => "content",
                "data" => %{"type" => "html", "data" => %{"text" => "<b>x</b>"}}
              }
            ],
            "vars" => [],
            "children" => []
          }
        }
      ]
    }

    draft = %{ctx.draft | payload: %{"main" => %{}, "blocks" => blocks, "modules" => Modules.manifest(blocks)}}

    assert {:review, :modules_changed, [%{reasons: [reason]}]} =
             Restore.prepare(draft, ctx.page, Brando.Pages.Page, ctx.user)

    assert reason =~ "content"
  end

  test "a changed saved entry requires explicit confirmation", ctx do
    changed = %{ctx.page | updated_at: NaiveDateTime.add(ctx.page.updated_at, 10, :second)}
    assert {:review, :entry_changed, []} = Restore.prepare(ctx.draft, changed, Brando.Pages.Page, ctx.user)
    assert {:ok, _, []} = Restore.prepare(ctx.draft, changed, Brando.Pages.Page, ctx.user, accept_conflict: true)

    assert {:review, :entry_changed, []} =
             Restore.prepare(ctx.draft, %{ctx.page | title: "Changed in the same second"}, Brando.Pages.Page, ctx.user)
  end

  describe "a copy that moves the image of saved cards" do
    # `count` saved cards each hold the same image; the copy gives each its own
    setup ctx do
      {:ok, module} =
        Brando.Content.create_module(
          Factory.params_for(:module, vars: [%{key: "cover", label: "Cover", type: :image}]),
          ctx.user
        )

      %{module: module, saved: Factory.insert(:image)}
    end

    test "loads the moved images together, however many cards move", ctx do
      assert queries_restoring(ctx, 1) == queries_restoring(ctx, 4)
    end

    test "draws each card with its own image", ctx do
      {cs, images} = restore_cards(ctx, 3)

      covers =
        for join <- Changeset.get_assoc(cs, :entry_blocks),
            [var] = join |> Changeset.get_assoc(:block) |> Changeset.get_assoc(:vars),
            do: Changeset.apply_changes(var).image.id

      assert Enum.sort(covers) == Enum.sort(Enum.map(images, & &1.id))
    end

    defp queries_restoring(ctx, count) do
      test = self()
      handler = "restore-#{System.unique_integer([:positive])}"
      event = Repo.repo().config()[:telemetry_prefix] ++ [:query]
      :ok = :telemetry.attach(handler, event, fn _, _, _, _ -> if self() == test, do: send(test, :query) end, nil)

      try do
        restore_cards(ctx, count, fn -> flush_queries() end)
      after
        :telemetry.detach(handler)
      end

      flush_queries()
    end

    defp flush_queries(count \\ 0) do
      receive do
        :query -> flush_queries(count + 1)
      after
        0 -> count
      end
    end

    # Saves `count` cards on a page, then restores a copy giving each a new image
    defp restore_cards(ctx, count, before_restore \\ fn -> :ok end) do
      page = Factory.insert(:page, creator: ctx.user)

      for sequence <- 1..count do
        block =
          %Brando.Content.Block{}
          |> Brando.Content.Block.recursive_block_changeset(
            %{
              "uid" => Brando.Utils.generate_uid(),
              "type" => "module",
              "module_id" => ctx.module.id,
              "creator_id" => ctx.user.id,
              "source" => to_string(Brando.Pages.Page.Blocks)
            },
            ctx.user
          )
          |> Repo.insert!()

        Repo.insert!(%Brando.Content.Var{
          key: "cover",
          type: :image,
          label: %{"en" => "Cover"},
          image_id: ctx.saved.id,
          block_id: block.id,
          sequence: 0
        })

        Repo.insert!(%Brando.Pages.Page.Blocks{entry_id: page.id, block_id: block.id, sequence: sequence})
      end

      {:ok, page} = Brando.Blueprint.EntryQuery.get(Brando.Pages.Page, page.id)
      images = for _ <- 1..count, do: Factory.insert(:image)

      rows =
        page.entry_blocks
        |> Params.snapshot()
        |> Enum.zip(images)
        |> Enum.map(fn {row, image} ->
          update_in(row, ["block", "vars"], fn [var] -> [Map.put(var, "image_id", image.id)] end)
        end)

      blocks = %{"blocks" => rows}

      draft = %{
        format_version: 1,
        schema_version: Brando.Blueprint.Snapshot.get_current_version(Brando.Pages.Page),
        base_fingerprint: Drafts.fingerprint(page),
        payload: %{"main" => %{}, "blocks" => blocks, "modules" => Modules.manifest(blocks)}
      }

      before_restore.()
      assert {:ok, cs, []} = Restore.prepare(draft, page, Brando.Pages.Page, ctx.user)
      {cs, images}
    end
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
