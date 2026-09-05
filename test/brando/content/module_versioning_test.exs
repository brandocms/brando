defmodule Brando.Content.ModuleVersioningTest do
  @moduledoc """
  The version bump and the stale-block bookkeeping it drives, against the database.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Content.Module
  alias Brando.Factory
  alias Ecto.Changeset

  defp insert_module(user, attrs \\ %{}) do
    Factory.insert(:module, Map.merge(%{code: "<div>{% ref refs.h2 %}</div>"}, attrs))
    |> tap(fn _ -> user end)
  end

  defp save(module, params, user) do
    module
    |> Module.changeset(params, user)
    |> Brando.Repo.update()
  end

  describe "uid" do
    test "is generated for a new module" do
      user = Factory.insert(:random_user)

      {:ok, module} =
        %Module{}
        |> Module.changeset(
          %{
            name: %{"en" => "New"},
            namespace: %{"en" => "general"},
            help_text: %{"en" => "help"},
            class: "c",
            code: "code"
          },
          user
        )
        |> Brando.Repo.insert()

      assert is_binary(module.uid)
      assert module.uid != ""
    end

    test "survives an update untouched" do
      user = Factory.insert(:random_user)
      module = insert_module(user)
      {:ok, updated} = save(module, %{code: "changed"}, user)

      assert updated.uid == module.uid
    end
  end

  describe "version bumping" do
    test "a save that changes nothing does not bump" do
      user = Factory.insert(:random_user)
      module = insert_module(user)

      {:ok, updated} = save(module, %{}, user)

      assert updated.version == module.version
    end

    test "a metadata change bumps" do
      user = Factory.insert(:random_user)
      module = insert_module(user)

      {:ok, updated} = save(module, %{name: %{"en" => "Renamed"}}, user)

      assert updated.version == module.version + 1
    end

    test "a code change bumps" do
      user = Factory.insert(:random_user)
      module = insert_module(user)

      {:ok, updated} = save(module, %{code: "<p>different</p>"}, user)

      assert updated.version == module.version + 1
    end

    test "a version_note-only save does not bump" do
      user = Factory.insert(:random_user)
      module = insert_module(user)

      {:ok, updated} = save(module, %{version_note: "just a note"}, user)

      assert updated.version == module.version
    end

    test "successive effective saves keep counting" do
      user = Factory.insert(:random_user)
      module = insert_module(user)

      {:ok, v2} = save(module, %{code: "one"}, user)
      {:ok, v3} = save(v2, %{code: "two"}, user)

      assert v3.version == module.version + 2
    end

    test "an explicit version change is left alone" do
      user = Factory.insert(:random_user)
      module = insert_module(user)

      {:ok, updated} = save(module, %{code: "changed", version: 99}, user)

      assert updated.version == 99
    end
  end

  describe "the version bump as an optimistic lock" do
    test "a second editor saving over a revision they never saw is rejected" do
      user = Factory.insert(:random_user)
      module = insert_module(user)

      # Both editors opened the same revision.
      stale_copy = module

      {:ok, _} = save(module, %{code: "first editor wins"}, user)

      assert_raise Ecto.StaleEntryError, fn ->
        save(stale_copy, %{code: "second editor clobbers"}, user)
      end
    end

    test "a no-op save over a moved revision does not raise" do
      user = Factory.insert(:random_user)
      module = insert_module(user)
      stale_copy = module

      {:ok, _} = save(module, %{code: "moved on"}, user)

      # Nothing to publish, nothing to conflict over.
      assert {:ok, _} = save(stale_copy, %{}, user)
    end
  end

  describe "list_stale_block_ids/2" do
    setup do
      user = Factory.insert(:random_user)
      module = insert_module(user)
      %{user: user, module: module}
    end

    defp insert_block(module, user, module_version) do
      %Block{}
      |> Changeset.change(%{
        uid: Brando.Utils.generate_uid(),
        type: :module,
        module_id: module.id,
        module_version: module_version,
        creator_id: user.id,
        sequence: 0
      })
      |> Brando.Repo.insert!()
    end

    test "a block at the module's version is not stale", %{module: module, user: user} do
      block = insert_block(module, user, module.version)

      refute block.id in ContentBlocks.list_stale_block_ids(module)
      assert ContentBlocks.count_stale_blocks(module) == 0
    end

    test "a block behind the module is stale", %{module: module, user: user} do
      block = insert_block(module, user, module.version - 1)

      assert block.id in ContentBlocks.list_stale_block_ids(module)
      assert ContentBlocks.count_stale_blocks(module) == 1
    end

    test "a block that predates tracking is stale", %{module: module, user: user} do
      block = insert_block(module, user, nil)

      assert block.id in ContentBlocks.list_stale_block_ids(module)
    end

    test "accepts a module id and reads the version from the row", %{module: module, user: user} do
      block = insert_block(module, user, nil)

      assert block.id in ContentBlocks.list_stale_block_ids(module.id)
    end

    test "an unknown module id yields nothing rather than raising" do
      assert ContentBlocks.list_stale_block_ids(-1) == []
    end

    test "blocks of other modules are not counted", %{module: module, user: user} do
      other = insert_module(user)
      insert_block(other, user, nil)

      assert ContentBlocks.count_stale_blocks(module) == 0
    end
  end
end
