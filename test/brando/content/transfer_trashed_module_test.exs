defmodule Brando.Content.TransferTrashedModuleTest do
  # A content transfer does not bring back a block of a module in the trash
  # (#3923): an import refuses it by name when the module went to the trash
  # after the preview, and a recovery refuses the blocks it would put back.
  # The source's module is mapped to another module on the destination, so
  # the one in the trash has another id than the bundle's.
  use Brando.ConnCase, async: false

  alias Brando.Content.Block
  alias Brando.Content.Transfer
  alias Brando.Content.Transfer.{Catalog, Receipt}
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Repo
  alias Brando.Utils
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user, role: :superuser)
    source = Factory.insert(:page, creator: user, title: "Source", status: :draft)
    target = Factory.insert(:page, creator: user, title: "Destination", status: :draft)
    module = text_module!("Text", user)
    mapped = text_module!("Mapped text", user, uid: "mappedtx")
    add_block!(source, module, user)

    %{
      user: user,
      source: source,
      target: target,
      module: module,
      mapped: mapped,
      mapping: %{"module:#{module.id}" => mapped.id}
    }
  end

  describe "a field import" do
    test "of a block whose module went to the trash after the preview is refused by name", c do
      plan = field_plan(c, export_field(c))
      assert plan.problems == []
      {:ok, _} = Brando.Content.delete_module(c.mapped.id, c.user)

      assert {:error, message} = Transfer.apply(plan, c.user)
      assert message =~ "Mapped text"
      assert message =~ "Destination"
      assert blocks(c.target, c.user) == []
      assert Repo.aggregate(Receipt, :count) == 0
      assert staged(plan) == []
    end

    # A preview binds a module only for someone who may read it: this one
    # loses that between the preview and the import
    test "names no module to someone who may no longer read modules", c do
      editor = import_editor!(c.user)
      readers = module_readers!(c.user, editor)
      plan = field_plan(c, export_field(c), "replace", nil, editor)
      assert plan.problems == []

      {:ok, _} =
        Brando.Authorization.Groups.remove_member(Brando.Authorization.Scope.standalone(c.user), readers.id, editor.id)

      {:ok, _} = Brando.Content.delete_module(c.mapped.id, c.user)

      assert {:error, message} = Transfer.apply(plan, editor)
      assert message =~ "Destination"
      refute message =~ "Mapped text"
      assert blocks(c.target, c.user) == []
    end

    test "names the module to someone in a group that may read modules", c do
      editor = import_editor!(c.user)
      module_readers!(c.user, editor)
      plan = field_plan(c, export_field(c), "replace", nil, editor)
      assert plan.problems == []
      {:ok, _} = Brando.Content.delete_module(c.mapped.id, c.user)

      assert {:error, message} = Transfer.apply(plan, editor)
      assert message =~ "Mapped text"
      assert blocks(c.target, c.user) == []
    end

    test "that keeps a held block of such a module, appending to it, goes through", c do
      add_block!(c.target, c.mapped, c.user)
      plan = field_plan(c, export_field(c), "append", %{"module:#{c.module.id}" => c.module.id})
      assert plan.problems == []
      trash!(c.mapped)

      assert {:ok, _receipt} = Transfer.apply(plan, c.user)
      assert [%{module_id: held}, %{module_id: added}] = blocks(c.target, c.user)
      assert {held, added} == {c.mapped.id, c.module.id}
    end

    test "that committed returns its receipt again after the module went to the trash", c do
      plan = field_plan(c, export_field(c))
      assert {:ok, receipt} = Transfer.apply(plan, c.user)
      trash!(c.mapped)

      assert {:ok, %Receipt{id: id}} = Transfer.apply(plan, c.user)
      assert id == receipt.id
    end
  end

  describe "a whole-entry import" do
    test "refuses by name, and leaves the entries before it unchanged", c do
      other = Factory.insert(:page, creator: c.user, title: "Other source", status: :draft)
      second = Factory.insert(:page, creator: c.user, title: "Second destination", status: :draft)
      archive = entry_archive(c, [%{schema: Page, id: other.id}, %{schema: Page, id: c.source.id}])
      assert [%{"key" => other_key}, %{"key" => source_key}] = archive.bundle["entries"]

      targets = %{
        other_key => update_target(second),
        source_key => update_target(c.target)
      }

      assert {:ok, plan} = Transfer.preview(archive, targets, c.user, dependencies: c.mapping)
      assert plan.problems == []
      {:ok, _} = Brando.Content.delete_module(c.mapped.id, c.user)

      assert {:error, message} = Transfer.apply(plan, c.user)
      assert message =~ "Mapped text"
      assert Repo.get!(Page, second.id).title == "Second destination"
      assert blocks(c.target, c.user) == []
      assert Repo.aggregate(Receipt, :count) == 0
      assert staged(plan) == []
    end

    test "that committed returns its receipt again after the module went to the trash", c do
      plan = entry_plan(c)
      assert {:ok, receipt} = Transfer.apply(plan, c.user)
      trash!(c.mapped)

      assert {:ok, %Receipt{id: id}} = Transfer.apply(plan, c.user)
      assert id == receipt.id
    end
  end

  describe "a preview mapping to a module in the trash" do
    setup c do
      {:ok, _} = Brando.Content.delete_module(c.mapped.id, c.user)
      :ok
    end

    test "names it to whoever may read modules", c do
      plan = field_plan(c, export_field(c))
      assert [issue] = for(%{issue: issue} <- plan.dependencies, issue, do: issue)
      assert issue =~ "Mapped text"
    end

    test "leaves its name out for someone who may import but not read modules", c do
      archive = export_field(c)
      editor = import_editor!(c.user)

      assert {:ok, plan} = Transfer.preview(archive, field_targets(c, archive), editor, dependencies: c.mapping)
      assert [issue] = for(%{issue: issue} <- plan.dependencies, issue, do: issue)
      refute issue =~ "Mapped text"
      refute Transfer.applicable?(plan)
    end
  end

  describe "a recovery that would put back a block of a module in the trash" do
    test "of a field is refused by name and can be retried once the module is restored", c do
      add_block!(c.target, c.mapped, c.user)
      plan = field_plan(c, export_field(c), "replace", %{"module:#{c.module.id}" => c.module.id})
      assert {:ok, receipt} = Transfer.apply(plan, c.user)
      {:ok, trashed} = Brando.Content.delete_module(c.mapped.id, c.user)

      assert {:error, message} = Transfer.restore(receipt.id, c.user)
      assert message =~ "Mapped text"
      assert [%{module_id: module_id}] = blocks(c.target, c.user)
      assert module_id == c.module.id
      assert is_nil(Repo.get!(Receipt, receipt.id).restored_at)

      {:ok, _} = Brando.Authorization.Boundary.restore(c.user, trashed)
      assert {:ok, _} = Transfer.restore(receipt.id, c.user)
      assert [%{module_id: module_id}] = blocks(c.target, c.user)
      assert module_id == c.mapped.id
    end

    test "of a whole entry is refused by name and can be retried once the module is restored", c do
      add_block!(c.target, c.mapped, c.user)
      assert {:ok, receipt} = Transfer.apply(entry_plan(c, %{"module:#{c.module.id}" => c.module.id}), c.user)
      {:ok, trashed} = Brando.Content.delete_module(c.mapped.id, c.user)

      assert {:error, message} = Transfer.restore(receipt.id, c.user)
      assert message =~ "Mapped text"
      assert [%{module_id: module_id}] = blocks(c.target, c.user)
      assert module_id == c.module.id
      assert is_nil(Repo.get!(Receipt, receipt.id).restored_at)

      {:ok, _} = Brando.Authorization.Boundary.restore(c.user, trashed)
      assert {:ok, _} = Transfer.restore(receipt.id, c.user)
      assert [%{module_id: module_id}] = blocks(c.target, c.user)
      assert module_id == c.mapped.id
    end
  end

  defp text_module!(name, user, opts \\ []) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          uid: opts[:uid] || Utils.generate_uid(),
          name: %{"en" => name},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: "{% ref refs.body %}",
          refs: [%{name: "body", uid: Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    module
  end

  defp add_block!(page, module, user) do
    params = %{
      "uid" => Utils.generate_uid(),
      "type" => "module",
      "module_id" => module.id,
      "creator_id" => user.id,
      "source" => to_string(Page.Blocks),
      "refs" => [
        %{
          "uid" => Utils.generate_uid(),
          "name" => "body",
          "data" => %{"type" => "text", "data" => %{"text" => "<p>Saved content</p>"}}
        }
      ]
    }

    block = %Block{} |> Block.recursive_block_changeset(params, user) |> Repo.insert!()
    sequence = Repo.aggregate(Ecto.Query.from(j in Page.Blocks, where: j.entry_id == ^page.id), :count)
    struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
  end

  # In the trash although blocks use it, as a site's data from before the
  # check can be
  defp trash!(module), do: module |> Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

  defp export_field(c) do
    assert {:ok, exported} = Transfer.export([%{schema: Page, id: c.source.id, fields: ["blocks"]}], c.user)
    assert {:ok, archive} = Transfer.read(exported.binary)
    archive
  end

  defp field_targets(c, archive) do
    [field] = archive.bundle["fields"]
    %{field["key"] => %{"schema" => to_string(Page), "id" => c.target.id, "field" => "blocks", "mode" => "replace"}}
  end

  defp field_plan(c, archive, mode \\ "replace", dependencies \\ nil, actor \\ nil) do
    targets = Map.new(field_targets(c, archive), fn {key, target} -> {key, %{target | "mode" => mode}} end)
    assert {:ok, plan} = Transfer.preview(archive, targets, actor || c.user, dependencies: dependencies || c.mapping)
    plan
  end

  defp entry_archive(c, selectors) do
    assert {:ok, exported} = Transfer.export(selectors, c.user, media: false)
    assert {:ok, archive} = Transfer.read(exported.binary)
    archive
  end

  defp entry_plan(c, dependencies \\ nil) do
    archive = entry_archive(c, [%{schema: Page, id: c.source.id}])
    [%{"key" => key}] = archive.bundle["entries"]
    targets = %{key => update_target(c.target)}
    assert {:ok, plan} = Transfer.preview(archive, targets, c.user, dependencies: dependencies || c.mapping)
    assert plan.problems == []
    plan
  end

  defp update_target(page),
    do: %{"mode" => "update", "id" => page.id, "publication" => "preserve", "attributes" => %{"uri" => page.uri}}

  defp blocks(page, user), do: Catalog.load!(Page, page.id, user).entry_blocks |> Enum.map(& &1.block)

  # What an import staged for `plan` and did not clean up
  defp staged(plan), do: Path.wildcard(Path.join(System.tmp_dir!(), "brando-content-#{plan.id}-*"))

  # A user who may read and update pages, but not read modules
  defp import_editor!(admin) do
    alias Brando.Authorization.{Catalog, Groups, Scope}

    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    editor = Factory.insert(:random_user, role: :user)
    grants = [Catalog.get(:read, Page).key, Catalog.get(:update, Page).key, "brando.admin.access"]
    {:ok, group} = Groups.create(Scope.standalone(admin), %{name: "Page importers"}, grants)
    {:ok, :ok} = Groups.add_member(Scope.standalone(admin), group.id, editor.id)
    editor
  end

  # A group that may read modules, with `editor` in it
  defp module_readers!(admin, editor) do
    alias Brando.Authorization.{Catalog, Groups, Scope}

    grants = [Catalog.get(:read, Brando.Content.Module).key]
    {:ok, group} = Groups.create(Scope.standalone(admin), %{name: "Module readers"}, grants)
    {:ok, :ok} = Groups.add_member(Scope.standalone(admin), group.id, editor.id)
    group
  end
end
