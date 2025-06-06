defmodule Brando.ContentTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Content
  alias Brando.Content.Var
  alias Brando.Content.Module
  alias Brando.Content.Module.Ref

  describe "module export/import with children" do
    test "prepare_modules_for_export/2 handles multi modules with children" do
      user = Factory.insert(:random_user)

      # Create parent module
      parent_attrs = %{
        name: %{"en" => "Parent", "no" => "Forelder"},
        namespace: %{"en" => "test", "no" => "test"},
        help_text: %{"en" => "Help", "no" => "Hjelp"},
        class: "parent",
        code: "<div>{{ content }}</div>",
        multi: true,
        refs: [
          %{
            name: "TestRef",
            description: "A test ref",
            data: %{type: "text", data: %{text: "Hello"}},
            uid: "abc123"
          }
        ],
        vars: []
      }

      {:ok, parent} = Content.create_module(parent_attrs, user)

      # Create child modules
      child_attrs = %{
        name: %{"en" => "Child 1", "no" => "Barn 1"},
        namespace: %{"en" => "test", "no" => "test"},
        help_text: %{"en" => "Child 1", "no" => "Barn 1"},
        class: "child-1",
        code: "<p>Child 1</p>",
        parent_id: parent.id,
        sequence: 0,
        refs: [],
        vars: []
      }

      {:ok, child} = Content.create_module(child_attrs, user)

      # Add a var directly to the parent module
      var = %Var{
        type: :text,
        label: "Test Variable",
        key: "test_var",
        value: "Test Value",
        creator_id: user.id,
        module_id: parent.id,
        sequence: 0
      }

      {:ok, _var} = Brando.Repo.insert(var)

      # Load modules with children and vars
      modules =
        Content.list_modules!(%{
          filter: %{ids: [parent.id]},
          preload: [:vars, children: [:vars]]
        })

      # Prepare for export
      prepared_modules = Content.prepare_modules_for_export(modules, user.id)

      assert length(prepared_modules) == 1
      [prepared_parent] = prepared_modules

      # Parent module assertions
      assert prepared_parent.id == nil
      assert prepared_parent.name == parent.name
      assert prepared_parent.multi == true

      # Refs should have new UIDs
      assert length(prepared_parent.refs) == 1
      [prepared_ref] = prepared_parent.refs
      assert prepared_ref.name == "TestRef"
      assert prepared_ref.data.uid != "abc123"

      # Vars should have no IDs
      assert length(prepared_parent.vars) == 1
      [prepared_var] = prepared_parent.vars
      assert prepared_var.id == nil
      assert prepared_var.key == "test_var"
      assert prepared_var.creator_id == user.id

      # Children should be prepared
      assert length(prepared_parent.children) == 1
      [prepared_child] = prepared_parent.children
      assert prepared_child.id == nil
      assert prepared_child.parent_id == nil
      assert prepared_child.name == child.name
    end

    test "import_module_with_children/1 maintains parent-child relationships" do
      user = Factory.insert(:random_user)

      # First create a module and export it to get the correct structure
      {:ok, original_parent} =
        Content.create_module(
          %{
            name: %{"en" => "Original Parent"},
            namespace: %{"en" => "original"},
            help_text: %{"en" => "Original help"},
            class: "original-parent",
            code: "<div>{{ content }}</div>",
            multi: true,
            refs: [],
            vars: []
          },
          user
        )

      {:ok, _child1} =
        Content.create_module(
          %{
            name: %{"en" => "Original Child 1"},
            namespace: %{"en" => "original"},
            help_text: %{"en" => "Child 1 help"},
            class: "original-child-1",
            code: "<p>Child 1</p>",
            parent_id: original_parent.id,
            sequence: 0,
            refs: [],
            vars: []
          },
          user
        )

      {:ok, _child2} =
        Content.create_module(
          %{
            name: %{"en" => "Original Child 2"},
            namespace: %{"en" => "original"},
            help_text: %{"en" => "Child 2 help"},
            class: "original-child-2",
            code: "<p>Child 2</p>",
            parent_id: original_parent.id,
            sequence: 1,
            refs: [],
            vars: []
          },
          user
        )

      # Export and prepare the module
      modules =
        Content.list_modules!(%{
          filter: %{ids: [original_parent.id]},
          preload: [:vars, children: [:vars]]
        })

      [orig_module] = modules
      [prepared_module] = Content.prepare_modules_for_export(modules, user.id)

      # Delete original
      {:ok, _} = Content.delete_module(orig_module.id)
      # Delete children
      for child <- orig_module.children do
        {:ok, _} = Content.delete_module(child.id)
      end

      # Import the prepared module
      {:ok, imported_parent} = Content.import_module_with_children(prepared_module)

      # Reload with children
      parent_with_children =
        Content.get_module!(%{
          matches: %{id: imported_parent.id},
          preload: [:children]
        })

      assert parent_with_children.name == %{"en" => "Original Parent"}
      assert parent_with_children.multi == true
      assert length(parent_with_children.children) == 2

      # Verify children have correct parent_id and sequence
      children = Enum.sort_by(parent_with_children.children, & &1.sequence)
      [child1, child2] = children

      assert child1.parent_id == parent_with_children.id
      assert child1.sequence == 0
      assert child1.class == "original-child-1"

      assert child2.parent_id == parent_with_children.id
      assert child2.sequence == 1
      assert child2.class == "original-child-2"
    end

    test "full export/import cycle preserves structure" do
      user = Factory.insert(:random_user)
      # Create complex module structure

      child1 = %Module{
        name: %{"en" => "Complex Child 1"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "Child 1"},
        class: "complex-child-1",
        code: "<p>Child 1</p>",
        sequence: 0,
        refs: [
          %Ref{
            name: "TestRefChild1",
            description: "A test ref",
            data: %Brando.Villain.Blocks.TextBlock{
              uid: "abc123",
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "Hello"}
            }
          }
        ],
        vars: [
          %Var{
            type: :text,
            label: "Child1 Variable",
            key: "child1_var",
            value: "Child1 Value",
            creator_id: user.id,
            sequence: 0
          }
        ]
      }

      child2 = %Module{
        name: %{"en" => "Complex Child 2"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "Child 2"},
        class: "complex-child-2",
        code: "<p>Child 2</p>",
        sequence: 1,
        refs: [
          %Ref{
            name: "TestRefChild2",
            description: "A test ref",
            data: %Brando.Villain.Blocks.TextBlock{
              uid: "abc123",
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "Hello"}
            }
          }
        ],
        vars: [
          %Var{
            type: :text,
            label: "Child2 Variable",
            key: "child2_var",
            value: "Child2 Value",
            creator_id: user.id,
            sequence: 0
          }
        ]
      }

      parent_struct = %Module{
        name: %{"en" => "Complex Parent"},
        namespace: %{"en" => "complex"},
        help_text: %{"en" => "Complex help"},
        class: "complex-parent",
        code: "<div>{{ content }}</div>",
        multi: true,
        refs: [
          %Ref{
            name: "ParentRef",
            description: "A test ref",
            data: %Brando.Villain.Blocks.TextBlock{
              uid: "abc123",
              type: "text",
              data: %Brando.Villain.Blocks.TextBlock.Data{text: "Hello"}
            }
          }
        ],
        vars: [
          %Var{
            type: :text,
            label: "Parent Variable",
            key: "parent_var",
            value: "Parent Value",
            creator_id: user.id,
            sequence: 0
          }
        ],
        children: [child1, child2]
      }

      parent = Brando.Repo.insert!(parent_struct)
      # Export
      modules =
        Content.list_modules!(%{
          filter: %{ids: [parent.id]},
          preload: [:vars, children: [:vars]]
        })

      prepared = Content.prepare_modules_for_export(modules, user.id)
      encoded = Content.serialize_modules(prepared)

      # Delete original
      {:ok, _} = Content.delete_module(parent.id)
      # Delete children
      for child <- parent.children do
        {:ok, _} = Content.delete_module(child.id)
      end

      # ensure we have no modules left
      assert Content.list_modules!() == []

      # Import
      decoded = Content.deserialize_modules(encoded)

      for mod <- decoded do
        Content.import_module_with_children(mod)
      end

      # Verify
      imported =
        Content.list_modules!(%{
          filter: %{namespace: "complex"},
          preload: [:vars, :children]
        })

      assert length(imported) == 1
      [imported_parent] = imported

      assert imported_parent.name == %{"en" => "Complex Parent"}
      assert length(imported_parent.children) == 2
      assert length(imported_parent.vars) == 1
      assert length(imported_parent.refs) == 1

      [child1, child2] = imported_parent.children
      assert child1.name == %{"en" => "Complex Child 1"}
      assert child2.name == %{"en" => "Complex Child 2"}

      # assert that we changed the uid of the refs
      assert Enum.at(imported_parent.refs, 0).data.uid != "abc123"
      assert Enum.at(child1.refs, 0).data.uid != "abc123"
      assert Enum.at(child2.refs, 0).data.uid != "abc123"
    end
  end
end
