defmodule Brando.ContentTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Content
  alias Brando.Content.Var
  alias Brando.Factory

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
            uid: Brando.Utils.generate_uid(),
            data: %{
              type: "text",
              data: %{text: "Hello"}
            }
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

      # Load modules with children, vars and refs
      modules =
        Content.list_modules!(%{
          filter: %{ids: [parent.id]},
          preload: [:vars, :refs, children: [:vars, :refs]]
        })

      # Prepare for export
      prepared_modules = Content.prepare_modules_for_export(modules, user.id)

      assert length(prepared_modules) == 1
      [prepared_parent] = prepared_modules

      # Parent module assertions
      assert prepared_parent.id == nil
      assert prepared_parent.name == parent.name
      assert prepared_parent.multi == true

      # Refs should have new UIDs during export
      assert length(prepared_parent.refs) == 1
      [prepared_ref] = prepared_parent.refs
      assert prepared_ref.name == "TestRef"
      assert prepared_ref.uid != "abc123"

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
          preload: [:vars, :refs, children: [:vars, :refs]]
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

      # Create the parent module
      parent_attrs = %{
        name: %{"en" => "Complex Parent"},
        namespace: %{"en" => "complex"},
        help_text: %{"en" => "Complex help"},
        class: "complex-parent",
        code: "<div>{{ content }}</div>",
        multi: true,
        refs: [
          %{
            name: "ParentRef",
            description: "A test ref",
            uid: Brando.Utils.generate_uid(),
            data: %{
              type: "text",
              data: %{text: "Hello"}
            }
          }
        ],
        vars: [
          %{
            type: :text,
            label: "Parent Variable",
            key: "parent_var",
            value: "Parent Value",
            creator_id: user.id,
            sequence: 0
          }
        ]
      }

      {:ok, parent} = Content.create_module(parent_attrs, user)

      # Create child modules
      child1_attrs = %{
        name: %{"en" => "Complex Child 1"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "Child 1"},
        class: "complex-child-1",
        code: "<p>Child 1</p>",
        sequence: 0,
        parent_id: parent.id,
        refs: [
          %{
            name: "TestRefChild1",
            description: "A test ref",
            uid: Brando.Utils.generate_uid(),
            data: %{
              type: "text",
              data: %{text: "Hello"}
            }
          }
        ],
        vars: [
          %{
            type: :text,
            label: "Child1 Variable",
            key: "child1_var",
            value: "Child1 Value",
            creator_id: user.id,
            sequence: 0
          }
        ]
      }

      {:ok, _child1} = Content.create_module(child1_attrs, user)

      child2_attrs = %{
        name: %{"en" => "Complex Child 2"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "Child 2"},
        class: "complex-child-2",
        code: "<p>Child 2</p>",
        sequence: 1,
        parent_id: parent.id,
        refs: [
          %{
            name: "TestRefChild2",
            description: "A test ref",
            uid: Brando.Utils.generate_uid(),
            data: %{
              type: "text",
              data: %{text: "Hello"}
            }
          }
        ],
        vars: [
          %{
            type: :text,
            label: "Child2 Variable",
            key: "child2_var",
            value: "Child2 Value",
            creator_id: user.id,
            sequence: 0
          }
        ]
      }

      {:ok, _child2} = Content.create_module(child2_attrs, user)

      # Export
      modules =
        Content.list_modules!(%{
          filter: %{ids: [parent.id]},
          preload: [:vars, :refs, children: [:vars, :refs]]
        })

      prepared = Content.prepare_modules_for_export(modules, user.id)
      encoded = Content.serialize_modules(prepared)

      # Delete original
      # Load parent with children to delete them
      parent_with_children = Content.get_module!(%{matches: %{id: parent.id}, preload: [:children]})

      {:ok, _} = Content.delete_module(parent_with_children.id)
      # Delete children
      for child <- parent_with_children.children do
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
          preload: [:vars, :refs, :children]
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

      # Load children with refs to check UIDs - new UIDs should be generated during import
      child1_with_refs = Content.get_module!(%{matches: %{id: child1.id}, preload: [:refs]})
      child2_with_refs = Content.get_module!(%{matches: %{id: child2.id}, preload: [:refs]})

      # Assert that new UIDs were generated during import (different from original "abc123")
      parent_ref_uid = Enum.at(imported_parent.refs, 0).uid
      child1_ref_uid = Enum.at(child1_with_refs.refs, 0).uid
      child2_ref_uid = Enum.at(child2_with_refs.refs, 0).uid

      # All UIDs should be different from the original
      assert parent_ref_uid != "abc123"
      assert child1_ref_uid != "abc123"
      assert child2_ref_uid != "abc123"

      # All UIDs should be unique (proper cloning behavior)
      assert parent_ref_uid != child1_ref_uid
      assert parent_ref_uid != child2_ref_uid
      assert child1_ref_uid != child2_ref_uid
    end

    test "export/import cycle includes table templates and deduplicates by name" do
      user = Factory.insert(:random_user)

      # Create two different table templates
      {:ok, parent_template} =
        Content.create_table_template(
          %{
            name: "ParentTemplate",
            vars: [
              %{
                type: :string,
                label: "Column 1",
                key: "col1",
                sequence: 0,
                creator_id: user.id
              },
              %{
                type: :text,
                label: "Column 2",
                key: "col2",
                sequence: 1,
                creator_id: user.id
              }
            ]
          },
          user
        )

      {:ok, child_template} =
        Content.create_table_template(
          %{
            name: "ChildTemplate",
            vars: [
              %{
                type: :string,
                label: "Name",
                key: "name",
                sequence: 0,
                creator_id: user.id
              }
            ]
          },
          user
        )

      # Create a parent module with its own table template
      {:ok, parent} =
        Content.create_module(
          %{
            name: %{"en" => "Table Module"},
            namespace: %{"en" => "table_test"},
            help_text: %{"en" => "A module with table template"},
            class: "table-module",
            code: "<div>{{ content }}</div>",
            multi: true,
            table_template_id: parent_template.id,
            refs: [],
            vars: []
          },
          user
        )

      # Create a child with a different table template
      {:ok, _child} =
        Content.create_module(
          %{
            name: %{"en" => "Table Child"},
            namespace: %{"en" => "table_test"},
            help_text: %{"en" => "Child with table template"},
            class: "table-child",
            code: "<p>Child</p>",
            parent_id: parent.id,
            sequence: 0,
            table_template_id: child_template.id,
            refs: [],
            vars: []
          },
          user
        )

      # Export
      modules =
        Content.list_modules!(%{
          filter: %{ids: [parent.id]},
          preload: [
            :vars,
            :refs,
            table_template: [:vars],
            children: [:vars, :refs, table_template: [:vars]]
          ]
        })

      prepared = Content.prepare_modules_for_export(modules, user.id)

      # Verify table templates were prepared (IDs stripped)
      [prepared_parent] = prepared
      assert prepared_parent.table_template.id == nil
      assert prepared_parent.table_template.name == "ParentTemplate"
      assert length(prepared_parent.table_template.vars) == 2
      assert Enum.all?(prepared_parent.table_template.vars, &is_nil(&1.id))
      assert prepared_parent.table_template_id == nil

      [prepared_child] = prepared_parent.children
      assert prepared_child.table_template.id == nil
      assert prepared_child.table_template.name == "ChildTemplate"
      assert length(prepared_child.table_template.vars) == 1
      assert prepared_child.table_template_id == nil

      # Serialize and deserialize
      encoded = Content.serialize_modules(prepared)
      decoded = Content.deserialize_modules(encoded)

      # Delete originals
      parent_with_children =
        Content.get_module!(%{matches: %{id: parent.id}, preload: [:children]})

      for child <- parent_with_children.children do
        {:ok, _} = Content.delete_module(child.id)
      end

      {:ok, _} = Content.delete_module(parent_with_children.id)

      # Import — both table templates still exist in DB,
      # so they should be found by name (deduplicated, not duplicated)
      for mod <- decoded do
        {:ok, _} = Content.import_module_with_children(mod, user)
      end

      # Verify neither table template was duplicated
      parent_templates =
        Content.list_table_templates!(%{filter: %{name: "ParentTemplate"}})

      assert length(parent_templates) == 1
      assert hd(parent_templates).id == parent_template.id

      child_templates =
        Content.list_table_templates!(%{filter: %{name: "ChildTemplate"}})

      assert length(child_templates) == 1
      assert hd(child_templates).id == child_template.id

      # Verify imported modules reference the correct existing table templates
      imported =
        Content.list_modules!(%{
          filter: %{namespace: "table_test", parent_id: nil},
          preload: [:table_template, children: [:table_template]]
        })

      assert length(imported) == 1
      [imported_parent] = imported
      assert imported_parent.table_template_id == parent_template.id

      [imported_child] = imported_parent.children
      assert imported_child.table_template_id == child_template.id
    end

    test "import creates table template when it doesn't exist" do
      user = Factory.insert(:random_user)

      # Create module with table template, export, then delete everything
      {:ok, table_template} =
        Content.create_table_template(
          %{
            name: "ImportNewTemplate",
            vars: [
              %{
                type: :string,
                label: "Name",
                key: "name",
                sequence: 0,
                creator_id: user.id
              }
            ]
          },
          user
        )

      {:ok, module} =
        Content.create_module(
          %{
            name: %{"en" => "New TT Module"},
            namespace: %{"en" => "new_tt_test"},
            help_text: %{"en" => "Module"},
            class: "new-tt-module",
            code: "<div></div>",
            table_template_id: table_template.id,
            refs: [],
            vars: []
          },
          user
        )

      modules =
        Content.list_modules!(%{
          filter: %{ids: [module.id]},
          preload: [:vars, :refs, table_template: [:vars], children: [:vars, :refs, table_template: [:vars]]]
        })

      prepared = Content.prepare_modules_for_export(modules, user.id)
      encoded = Content.serialize_modules(prepared)

      # Delete everything — module and table template
      {:ok, _} = Content.delete_module(module.id)
      {:ok, _} = Content.delete_table_template(table_template.id)

      # Verify template is gone
      assert {:error, _} = Content.get_table_template(%{matches: %{name: "ImportNewTemplate"}})

      # Import
      decoded = Content.deserialize_modules(encoded)

      for mod <- decoded do
        {:ok, _} = Content.import_module_with_children(mod, user)
      end

      # The table template should have been re-created
      assert {:ok, new_tt} = Content.get_table_template(%{matches: %{name: "ImportNewTemplate"}, preload: [:vars]})
      assert new_tt.id != table_template.id
      assert length(new_tt.vars) == 1
      assert hd(new_tt.vars).key == "name"

      # Module should reference the new template
      imported =
        Content.list_modules!(%{
          filter: %{namespace: "new_tt_test", parent_id: nil},
          preload: [:table_template]
        })

      assert length(imported) == 1
      [imported_mod] = imported
      assert imported_mod.table_template_id == new_tt.id
    end
  end
end
