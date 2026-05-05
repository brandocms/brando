defmodule Brando.Blueprint.ConstraintsTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Blueprint.Constraints
  alias Brando.Blueprint.Relations.Relation
  alias Brando.Factory

  defmodule P1 do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Projects",
      schema: "Project",
      singular: "project",
      plural: "projects",
      gettext_module: Brando.Gettext

    attributes do
      attribute :title, :string, unique: true
    end
  end

  test "unique" do
    _cs = __MODULE__.P1.changeset(%__MODULE__.P1{}, %{title: "Hepp"}, %{id: 1})
  end

  describe "require_blocks" do
    test "passes when required block class is present" do
      user = Factory.insert(:random_user)

      {:ok, header_module} =
        Brando.Content.create_module(
          %{
            code: "HEADER",
            name: "Header",
            help_text: "Help",
            refs: [],
            namespace: "Headers",
            class: "header"
          },
          user
        )

      entry_blocks = [
        %Brando.Pages.Page.Blocks{
          block: %Brando.Content.Block{
            type: :module,
            module_id: header_module.id,
            active: true,
            uid: "test-uid-123",
            refs: [],
            vars: []
          }
        }
        |> Ecto.Changeset.change()
        |> Map.put(:action, :insert)
      ]

      page_params = Factory.params_for(:page)
      page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
      page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, entry_blocks)

      relation = %Relation{
        name: :blocks,
        type: :has_many,
        opts: %{module: :blocks, constraints: [require_blocks: ["header"]]}
      }

      result = Constraints.run_validations(page_cs, Brando.Pages.Page, [relation])
      assert result.errors == []
    end

    test "fails when required block class is missing" do
      user = Factory.insert(:random_user)

      {:ok, other_module} =
        Brando.Content.create_module(
          %{
            code: "OTHER",
            name: "Other",
            help_text: "Help",
            refs: [],
            namespace: "Other",
            class: "other"
          },
          user
        )

      entry_blocks = [
        %Brando.Pages.Page.Blocks{
          block: %Brando.Content.Block{
            type: :module,
            module_id: other_module.id,
            active: true,
            uid: "test-uid-456",
            refs: [],
            vars: []
          }
        }
        |> Ecto.Changeset.change()
        |> Map.put(:action, :insert)
      ]

      page_params = Factory.params_for(:page)
      page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
      page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, entry_blocks)

      relation = %Relation{
        name: :blocks,
        type: :has_many,
        opts: %{module: :blocks, constraints: [require_blocks: ["header"]]}
      }

      result = Constraints.run_validations(page_cs, Brando.Pages.Page, [relation])

      assert {:entry_blocks, {"is missing required block: %{class}", [class: "header", validation: :require_blocks]}} in result.errors
    end

    test "skips validation for drafts" do
      user = Factory.insert(:random_user)

      entry_blocks = [
        %Brando.Pages.Page.Blocks{
          block: %Brando.Content.Block{
            type: :module,
            module_id: nil,
            active: true,
            uid: "test-uid-789",
            refs: [],
            vars: []
          }
        }
        |> Ecto.Changeset.change()
        |> Map.put(:action, :insert)
      ]

      page_params = Factory.params_for(:page, %{status: :draft})
      page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
      page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, entry_blocks)

      relation = %Relation{
        name: :blocks,
        type: :has_many,
        opts: %{module: :blocks, constraints: [require_blocks: ["header"]]}
      }

      result = Constraints.run_validations(page_cs, Brando.Pages.Page, [relation])
      assert result.errors == []
    end

    test "skips validation when blocks are not being changed" do
      user = Factory.insert(:random_user)

      page_params = Factory.params_for(:page)
      page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)

      relation = %Relation{
        name: :blocks,
        type: :has_many,
        opts: %{module: :blocks, constraints: [require_blocks: ["header"]]}
      }

      result = Constraints.run_validations(page_cs, Brando.Pages.Page, [relation])
      assert result.errors == []
    end

    test "ignores inactive blocks" do
      user = Factory.insert(:random_user)

      {:ok, header_module} =
        Brando.Content.create_module(
          %{
            code: "HEADER2",
            name: "Header2",
            help_text: "Help",
            refs: [],
            namespace: "Headers",
            class: "header2"
          },
          user
        )

      entry_blocks = [
        %Brando.Pages.Page.Blocks{
          block: %Brando.Content.Block{
            type: :module,
            module_id: header_module.id,
            active: false,
            uid: "test-uid-inactive",
            refs: [],
            vars: []
          }
        }
        |> Ecto.Changeset.change()
        |> Map.put(:action, :insert)
      ]

      page_params = Factory.params_for(:page)
      page_cs = Brando.Pages.Page.changeset(%Brando.Pages.Page{}, page_params, user)
      page_cs = Ecto.Changeset.put_assoc(page_cs, :entry_blocks, entry_blocks)

      relation = %Relation{
        name: :blocks,
        type: :has_many,
        opts: %{module: :blocks, constraints: [require_blocks: ["header2"]]}
      }

      result = Constraints.run_validations(page_cs, Brando.Pages.Page, [relation])

      assert {:entry_blocks, {"is missing required block: %{class}", [class: "header2", validation: :require_blocks]}} in result.errors
    end
  end
end
