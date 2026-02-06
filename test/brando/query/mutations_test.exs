defmodule Brando.Query.MutationsTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  import Ecto.Query
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Revisions

  defmodule TestContext do
    use Brando.Query

    mutation :create, Page
    mutation :update, Page
    mutation :delete, Page

    mutation :duplicate, {
      Page,
      change_fields: [:title, :uri]
    }

    query :single, Page do
      fn query -> from(q in query) end
    end

    matches Page do
      fn
        {:id, id}, query -> from(q in query, where: q.id == ^id)
      end
    end
  end

  defmodule TestContextWithCallback do
    use Brando.Query

    mutation :create, Page do
      fn entry ->
        {:ok, entry, :callback_executed}
      end
    end

    mutation :update, Page do
      fn entry ->
        {:ok, entry, :update_callback}
      end
    end

    mutation :delete, Page do
      fn entry ->
        {:ok, entry, :delete_callback}
      end
    end

    query :single, Page do
      fn query -> from(q in query) end
    end

    matches Page do
      fn
        {:id, id}, query -> from(q in query, where: q.id == ^id)
      end
    end
  end

  describe "create/5" do
    test "creates entry with valid params" do
      user = Factory.insert(:random_user)
      params = Factory.params_for(:page, title: "Test Page", uri: "test-page")

      {:ok, page} = TestContext.create_page(params, user)

      assert page.title == "Test Page"
      assert page.uri == "test-page"
      assert page.creator_id == user.id
    end

    test "returns error changeset with invalid params" do
      user = Factory.insert(:random_user)
      # Missing required fields
      params = %{}

      {:error, changeset} = TestContext.create_page(params, user)

      assert changeset.valid? == false
    end

    test "creates revision for revisioned schema" do
      user = Factory.insert(:random_user)
      params = Factory.params_for(:page, title: "Revisioned Page")

      {:ok, page} = TestContext.create_page(params, user)

      # Page has Trait.Revisioned, so a revision should be created
      {:ok, {_revision, {revision_number, _entry}}} = Revisions.get_last_revision(Page, page.id)
      assert revision_number == 0
    end

    test "executes callback block" do
      user = Factory.insert(:random_user)
      params = Factory.params_for(:page, title: "Callback Page")

      # Callback returns {:ok, entry, :callback_executed}
      result = TestContextWithCallback.create_page(params, user)
      assert {:ok, page, :callback_executed} = result
      assert page.title == "Callback Page"
    end

    test "respects notify?: false option" do
      user = Factory.insert(:random_user)
      params = Factory.params_for(:page, title: "No Notify Page")

      # This should not raise - we're just verifying the option is accepted
      {:ok, page} = TestContext.create_page(params, user, notify?: false)

      assert page.title == "No Notify Page"
    end

    test "respects pubsub?: false option" do
      user = Factory.insert(:random_user)
      params = Factory.params_for(:page, title: "No PubSub Page")

      {:ok, page} = TestContext.create_page(params, user, pubsub?: false)

      assert page.title == "No PubSub Page"
    end
  end

  describe "create_with_changeset/5" do
    test "creates entry from valid changeset" do
      user = Factory.insert(:random_user)
      params = Factory.params_for(:page, title: "Changeset Page")

      changeset = Page.changeset(%Page{}, params, user, nil, [])

      {:ok, page} = TestContext.create_page(changeset, user)

      assert page.title == "Changeset Page"
    end

    test "returns error from invalid changeset" do
      user = Factory.insert(:random_user)

      changeset =
        %Page{}
        |> Ecto.Changeset.change(%{})
        |> Ecto.Changeset.validate_required([:title, :uri])

      {:error, error_changeset} = TestContext.create_page(changeset, user)

      assert error_changeset.valid? == false
    end
  end

  describe "update/10 (via generated context function)" do
    test "updates entry with valid params" do
      user = Factory.insert(:random_user)
      page = Factory.insert(:page, title: "Original Title")

      {:ok, updated_page} = TestContext.update_page(page.id, %{title: "Updated Title"}, user)

      assert updated_page.title == "Updated Title"
    end

    test "returns error changeset with invalid params" do
      user = Factory.insert(:random_user)
      page = Factory.insert(:page, title: "Original")

      # Set title to nil which should fail validation
      {:error, changeset} = TestContext.update_page(page.id, %{title: nil}, user)

      assert changeset.valid? == false
    end

    test "returns unchanged entry when no changes" do
      user = Factory.insert(:random_user)
      page = Factory.insert(:page, title: "Same Title")

      {:ok, unchanged_page} = TestContext.update_page(page.id, %{title: "Same Title"}, user)

      assert unchanged_page.id == page.id
      assert unchanged_page.title == "Same Title"
    end

    test "creates revision on change" do
      user = Factory.insert(:random_user)
      params = Factory.params_for(:page, title: "Initial")
      {:ok, page} = TestContext.create_page(params, user)

      {:ok, _updated} = TestContext.update_page(page.id, %{title: "Changed"}, user)

      # Check that last revision is 1 (0 from create, 1 from update)
      {:ok, {_revision, {revision_number, _entry}}} = Revisions.get_last_revision(Page, page.id)
      assert revision_number == 1
    end

    test "accepts show_notification option" do
      user = Factory.insert(:random_user)
      page = Factory.insert(:page, title: "Notify Test")

      {:ok, updated} =
        TestContext.update_page(page.id, %{title: "Updated"}, user, show_notification: false)

      assert updated.title == "Updated"
    end

    test "executes callback block" do
      user = Factory.insert(:random_user)
      # Use regular context to create the page
      page = Factory.insert(:page, title: "Callback Update")

      {:ok, updated, :update_callback} =
        TestContextWithCallback.update_page(page.id, %{title: "New Title"}, user)

      assert updated.title == "New Title"
    end

    test "works with map containing id" do
      user = Factory.insert(:random_user)
      page = Factory.insert(:page, title: "Map ID Test")

      {:ok, updated} = TestContext.update_page(%{id: page.id}, %{title: "Via Map"}, user)

      assert updated.title == "Via Map"
    end
  end

  describe "update_with_changeset/6" do
    test "updates entry from changeset" do
      user = Factory.insert(:random_user)
      page = Factory.insert(:page, title: "Original")

      changeset = Page.changeset(page, %{title: "From Changeset"}, user, nil, [])

      {:ok, updated} = TestContext.update_page(changeset, user)

      assert updated.title == "From Changeset"
    end

    test "respects show_notification option" do
      user = Factory.insert(:random_user)
      page = Factory.insert(:page, title: "Changeset Update")

      changeset = Page.changeset(page, %{title: "Silent Update"}, user, nil, [])

      {:ok, updated} = TestContext.update_page(changeset, user, show_notification: false)

      assert updated.title == "Silent Update"
    end
  end

  describe "delete/7 (via generated context function)" do
    test "soft deletes entry (Page has SoftDelete trait)" do
      user = Factory.insert(:random_user)
      page = Factory.insert(:page, title: "To Delete")

      {:ok, deleted_page} = TestContext.delete_page(page.id, user)

      assert deleted_page.id == page.id

      # Entry should be soft deleted (deleted_at set)
      {:error, {:page, :not_found}} = TestContext.get_page(%{matches: %{id: page.id}})

      # But should be findable with_deleted
      {:ok, found} =
        TestContext.get_page(%{matches: %{id: page.id}, with_deleted: true})

      assert found.deleted_at != nil
    end

    test "executes callback block" do
      user = Factory.insert(:random_user)
      # Use Factory to create page, avoid callback context for creation
      page = Factory.insert(:page, title: "Delete Callback")

      {:ok, deleted, :delete_callback} = TestContextWithCallback.delete_page(page.id, user)

      assert deleted.id == page.id
    end

    test "works with :system user" do
      page = Factory.insert(:page, title: "System Delete")

      {:ok, deleted} = TestContext.delete_page(page.id)

      assert deleted.id == page.id
    end
  end

  describe "duplicate/7 (via generated context function)" do
    test "creates duplicate with new ID" do
      user = Factory.insert(:random_user)
      original = Factory.insert(:page, title: "Original Page", uri: "original-uri")

      {:ok, duplicate} = TestContext.duplicate_page(original.id, user)

      assert duplicate.id != original.id
      assert duplicate.title =~ "Original Page"
    end

    test "applies change_fields transformations" do
      user = Factory.insert(:random_user)
      original = Factory.insert(:page, title: "My Title", uri: "my-uri")

      {:ok, duplicate} = TestContext.duplicate_page(original.id, user)

      # change_fields: [:title, :uri] should append _dupl
      assert duplicate.title == "My Title_dupl"
      assert duplicate.uri == "my-uri_dupl"
    end

    test "sets status to draft" do
      user = Factory.insert(:random_user)
      original = Factory.insert(:page, title: "Published", status: :published)

      {:ok, duplicate} = TestContext.duplicate_page(original.id, user)

      assert duplicate.status == :draft
    end

    test "sets creator to current user" do
      original_user = Factory.insert(:random_user)
      new_user = Factory.insert(:random_user)
      original = Factory.insert(:page, title: "Creator Test", creator: original_user)

      {:ok, duplicate} = TestContext.duplicate_page(original.id, new_user)

      assert duplicate.creator_id == new_user.id
    end

    test "accepts override_opts" do
      user = Factory.insert(:random_user)
      original = Factory.insert(:page, title: "Override Test", uri: "override-uri")

      {:ok, duplicate} =
        TestContext.duplicate_page(original.id, user, merge_fields: %{title: "Custom Title"})

      assert duplicate.title == "Custom Title"
    end

    test "duplicates table rows with their vars" do
      user = Factory.insert(:random_user)

      module_params = Factory.params_for(:module, %{code: "table code"})
      {:ok, module} = Brando.Content.create_module(module_params, :system)

      page_params = Factory.params_for(:page, %{title: "Table Row Test", creator_id: user.id})
      page_cs = Page.changeset(%Page{}, page_params, user)

      entry_blocks = [
        %{
          block: %{
            uid: Brando.Utils.generate_uid(),
            type: :module,
            source: "Elixir.Brando.Pages.Page.Blocks",
            module_id: module.id,
            refs: [],
            vars: [],
            table_rows: [
              %{
                sequence: 0,
                vars: [
                  %{
                    type: :string,
                    label: "Column 1",
                    key: "col1",
                    value: "Row 1 Col 1",
                    sequence: 0,
                    creator_id: user.id
                  },
                  %{
                    type: :string,
                    label: "Column 2",
                    key: "col2",
                    value: "Row 1 Col 2",
                    sequence: 1,
                    creator_id: user.id
                  }
                ]
              },
              %{
                sequence: 1,
                vars: [
                  %{
                    type: :string,
                    label: "Column 1",
                    key: "col1",
                    value: "Row 2 Col 1",
                    sequence: 0,
                    creator_id: user.id
                  }
                ]
              }
            ]
          }
        }
      ]

      page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, entry_blocks)
      page_cs = Map.put(page_cs, :action, :insert)

      {:ok, page} = Brando.Pages.create_page(page_cs, user)

      # Verify the original page has table rows with vars
      {:ok, original} =
        TestContext.get_page(%{
          matches: %{id: page.id},
          preload: Brando.Blueprint.preloads_for(Page)
        })

      original_block = hd(original.entry_blocks).block
      assert length(original_block.table_rows) == 2

      original_row = hd(original_block.table_rows)
      assert length(original_row.vars) >= 1
      original_var_ids = Enum.map(original_row.vars, & &1.id)
      assert Enum.all?(original_var_ids, &(not is_nil(&1)))

      # Duplicate the page
      {:ok, duplicate} = TestContext.duplicate_page(page.id, user)

      # Reload the duplicate with full preloads
      {:ok, dup} =
        TestContext.get_page(%{
          matches: %{id: duplicate.id},
          preload: Brando.Blueprint.preloads_for(Page)
        })

      dup_block = hd(dup.entry_blocks).block

      # Table rows should be duplicated
      assert length(dup_block.table_rows) == 2

      # Each table row should have new IDs
      for dup_row <- dup_block.table_rows do
        assert dup_row.id != nil

        # Vars should be duplicated with new IDs
        assert length(dup_row.vars) >= 1

        for var <- dup_row.vars do
          assert var.id != nil
          refute var.id in original_var_ids
        end
      end

      # Verify var values are preserved
      dup_first_row = Enum.find(dup_block.table_rows, &(&1.sequence == 0))
      dup_first_row_values = Enum.map(dup_first_row.vars, & &1.value) |> Enum.sort()
      assert dup_first_row_values == Enum.sort(["Row 1 Col 1", "Row 1 Col 2"])
    end
  end
end
