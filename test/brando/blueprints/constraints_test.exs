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

  describe "one_of" do
    alias Brando.Blueprint.Assets.Asset

    # An entry that is valid with either field filled in, but not with neither.
    # Declared on meta_image, so that is where the error lands.
    defp one_of_asset(opts \\ %{}) do
      %Asset{
        name: :meta_image,
        type: :image,
        opts: Map.merge(%{constraints: [one_of: [:meta_image, :meta_title]]}, opts)
      }
    end

    defp validate(changeset, asset \\ nil) do
      Constraints.run_validations(changeset, Brando.Pages.Page, [asset || one_of_asset()])
    end

    defp page(attrs \\ %{}) do
      Ecto.Changeset.change(%Brando.Pages.Page{}, attrs)
    end

    test "passes when the declared field is present" do
      refute validate(page(%{meta_image_id: 1})).errors[:meta_image_id]
    end

    test "passes when only the *other* field is present" do
      refute validate(page(%{meta_title: "Fallback"})).errors[:meta_image_id]
    end

    test "fails when neither is present, with the error on the declared field" do
      changeset = validate(page())

      assert {:meta_image_id, {message, opts}} =
               Enum.find(changeset.errors, &(elem(&1, 0) == :meta_image_id))

      assert message == "requires one of: %{fields}"
      assert opts[:fields] == "meta_image, meta_title"
      assert opts[:validation] == :one_of
      assert opts[:one_of] == [:meta_image, :meta_title]
    end

    test "counts an asset set by id — the picker path" do
      refute validate(page(%{meta_image_id: 42})).errors[:meta_image_id]
    end

    test "counts an asset set as a struct — the upload path" do
      changeset =
        %Brando.Pages.Page{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:meta_image, %Brando.Images.Image{path: "x.jpg"})

      refute validate(changeset).errors[:meta_image_id]
    end

    test "an unloaded association does not count as present" do
      assert validate(page()).errors[:meta_image_id]
    end

    test "an asset error lands on its _id column, where the form reads it" do
      # field_base/1 takes the label's failed state from <field>_id, and
      # used_input? is only ever true for that hidden input — an error on the
      # association alone renders nothing.
      changeset = validate(page())

      assert Keyword.has_key?(changeset.errors, :meta_image_id)
      refute Keyword.has_key?(changeset.errors, :meta_image)
    end

    test "every field in the set is flagged, not just the declaring one" do
      changeset = validate(page())

      assert Keyword.has_key?(changeset.errors, :meta_image_id)
      assert Keyword.has_key?(changeset.errors, :meta_title)
    end

    test "a plain attribute keeps its own key" do
      asset = %Asset{
        name: :meta_title,
        type: :image,
        opts: %{constraints: [one_of: [:meta_title, :title]]}
      }

      changeset = Constraints.run_validations(page(), Brando.Pages.Page, [asset])

      assert Keyword.has_key?(changeset.errors, :meta_title)
      assert Keyword.has_key?(changeset.errors, :title)
    end

    test "an empty string does not count as present" do
      assert validate(page(%{meta_title: ""})).errors[:meta_image_id]
    end

    test "the message can be overridden, declared alongside the constraint" do
      asset = %Asset{
        name: :meta_image,
        type: :image,
        opts: %{
          constraints: [
            one_of: [:meta_image, :meta_title],
            one_of_message: "needs an image or a title"
          ]
        }
      }

      assert {"needs an image or a title", _} = validate(page(), asset).errors[:meta_image_id]
    end

    test "one_of_message alone is not treated as a constraint" do
      asset = %Asset{name: :meta_image, type: :image, opts: %{constraints: [one_of_message: "unused"]}}

      assert validate(page(), asset).errors == []
    end
  end

  describe "exactly_one_of" do
    alias Brando.Blueprint.Assets.Asset

    defp xor_asset(opts \\ %{}) do
      %Asset{
        name: :meta_image,
        type: :image,
        opts: Map.merge(%{constraints: [exactly_one_of: [:meta_image, :meta_title]]}, opts)
      }
    end

    defp xor_validate(changeset, asset \\ nil) do
      Constraints.run_validations(changeset, Brando.Pages.Page, [asset || xor_asset()])
    end

    defp xor_page(attrs \\ %{}) do
      Ecto.Changeset.change(%Brando.Pages.Page{}, attrs)
    end

    test "passes with exactly one present" do
      refute xor_validate(xor_page(%{meta_image_id: 1})).errors[:meta_image_id]
      refute xor_validate(xor_page(%{meta_title: "T"})).errors[:meta_image_id]
    end

    test "fails when none are present" do
      assert {_msg, opts} = xor_validate(xor_page()).errors[:meta_image_id]
      assert opts[:validation] == :exactly_one_of
      assert opts[:present] == 0
    end

    test "fails when more than one is present — the case one_of allows" do
      changeset = xor_validate(xor_page(%{meta_image_id: 1, meta_title: "T"}))

      assert {message, opts} = changeset.errors[:meta_image_id]
      assert message == "requires exactly one of: %{fields}"
      assert opts[:fields] == "meta_image, meta_title"
      assert opts[:present] == 2
    end

    test "the message can be overridden, declared alongside the constraint" do
      asset = %Asset{
        name: :meta_image,
        type: :image,
        opts: %{
          constraints: [
            exactly_one_of: [:meta_image, :meta_title],
            exactly_one_of_message: "pick an image or a video, not both"
          ]
        }
      }

      assert {"pick an image or a video, not both", _} =
               xor_validate(xor_page(%{meta_image_id: 1, meta_title: "T"}), asset).errors[:meta_image_id]
    end

    test "exactly_one_of_message alone is not treated as a constraint" do
      asset = %Asset{
        name: :meta_image,
        type: :image,
        opts: %{constraints: [exactly_one_of_message: "unused"]}
      }

      assert xor_validate(xor_page(), asset).errors == []
    end
  end

  # A validation only covers writes going through the changeset. Declaring the
  # database constraint is what turns everything else into a field error rather
  # than a raised Ecto.ConstraintError.
  describe "check" do
    alias Brando.Blueprint.Assets.Asset

    defp checked(constraints) do
      asset = %Asset{name: :meta_image, type: :image, opts: %{constraints: constraints}}

      %Brando.Pages.Page{}
      |> Ecto.Changeset.change()
      |> Constraints.run_validations(Brando.Pages.Page, [asset])
      |> Map.fetch!(:constraints)
    end

    test "registers a check constraint under the declared name" do
      assert [constraint] = checked(check: :must_have_one_media_type)

      assert constraint.type == :check
      assert constraint.constraint == "must_have_one_media_type"
      assert constraint.field == :meta_image
      assert constraint.error_message == "is invalid"
    end

    test "a keyword list carries a message per constraint" do
      assert [constraint] = checked(check: [must_have_one_media_type: "image or video"])

      assert constraint.constraint == "must_have_one_media_type"
      assert constraint.error_message == "image or video"
    end

    test "several constraints can be declared at once" do
      # Ecto prepends, so compare as a set rather than pinning its ordering.
      constraints = checked(check: [:first_check, :second_check])

      assert constraints |> Enum.map(& &1.constraint) |> Enum.sort() ==
               ["first_check", "second_check"]
    end

    test "check_message supplies the default for bare names" do
      assert [constraint] = checked(check: :some_check, check_message: "shared message")

      assert constraint.error_message == "shared message"
    end

    test "check_message alone is not treated as a constraint" do
      assert checked(check_message: "unused") == []
    end
  end
end
