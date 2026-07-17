defmodule Brando.Blueprint.IdentifiersTest do
  use ExUnit.Case

  alias Brando.BlueprintTest.Project
  alias Brando.Content.Var
  alias Brando.Exception.BlueprintError
  alias Brando.Pages.Page

  describe "__has_identifier__/0" do
    test "returns true for schemas with identifier template" do
      assert Page.__has_identifier__() == true
      assert Project.__has_identifier__() == true
    end

    test "returns false for schemas with identifier false" do
      assert Var.__has_identifier__() == false
    end
  end

  describe "__persist_identifier__/0" do
    test "returns true by default for schemas with identifier" do
      assert Page.__persist_identifier__() == true
    end

    test "returns false for schemas with persist_identifier false" do
      assert Var.__persist_identifier__() == false
      assert Brando.Content.Container.__persist_identifier__() == false
    end

    test "rejects non-boolean configuration with a contextual error" do
      module = Module.concat(__MODULE__, "InvalidPersistence#{System.unique_integer([:positive])}")

      error =
        assert_raise BlueprintError, fn ->
          Code.compile_quoted(
            quote do
              defmodule unquote(module) do
                import Brando.Blueprint.Identifier.DSL
                persist_identifier :sometimes
              end
            end
          )
        end

      assert Exception.message(error) == "persist_identifier expects true or false, got: :sometimes"
    end

    test "accepts booleans stored in compile-time module attributes" do
      module = Module.concat(__MODULE__, "AttributedPersistence#{System.unique_integer([:positive])}")

      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            import Brando.Blueprint.Identifier.DSL

            @persist_identifiers false
            persist_identifier @persist_identifiers
          end
        end
      )

      refute module.__persist_identifier__()
    end
  end

  describe "__identifier_preloads__/0" do
    test "returns empty list when identifier only references direct fields" do
      assert Page.__identifier_preloads__() == []
    end

    test "extracts relation preloads from Liquex identifier template" do
      # Project identifier is "{{ entry.title }} [{{ entry.id }}]" — no relations
      assert Project.__identifier_preloads__() == []
    end

    test "extracts deep Liquid relations and ignores unknown paths without creating atoms" do
      suffix = System.unique_integer([:positive])
      module = Module.concat(__MODULE__, "UnknownRelation#{suffix}")
      unknown_relation = "relation_that_does_not_exist_#{suffix}"

      quoted =
        quote do
          defmodule unquote(module) do
            use Brando.Blueprint,
              application: "Brando",
              domain: "IdentifierPreloadTest",
              schema: "UnknownRelation",
              singular: "unknown_relation",
              plural: "unknown_relations",
              gettext_module: Brando.Gettext

            identifier unquote("{{ entry.creator.config.content_language }} {{ entry.#{unknown_relation}.title }}")

            relations do
              relation :creator, :belongs_to, module: Brando.Users.User
            end
          end
        end

      Code.compile_quoted(quoted)

      assert module.__identifier_preloads__() == [:creator]

      assert_raise ArgumentError, fn ->
        String.to_existing_atom(unknown_relation)
      end
    end
  end

  test "__identifier__" do
    assert Page.__identifier__(%Page{id: 1, status: :draft, language: "en", uri: "about-us", title: "About Us"}) ==
             %Brando.Content.Identifier{
               cover: nil,
               entry_id: 1,
               id: nil,
               language: :en,
               schema: Brando.Pages.Page,
               status: :draft,
               title: "About Us",
               updated_at: nil,
               url: "/en/about-us"
             }

    project = %Project{
      id: 1,
      status: :published,
      cover: %Brando.Images.Image{
        path: "/dummy/image.jpg",
        sizes: %{
          "large" => "/dummy/large/8qti51006g6.jpg",
          "medium" => "/dummy/medium/8qti51006g6.jpg",
          "micro" => "/dummy/micro/8qti51006g6.jpg",
          "small" => "/dummy/small/8qti51006g6.jpg",
          "thumb" => "/dummy/thumb/8qti51006g6.jpg",
          "xlarge" => "/dummy/xlarge/8qti51006g6.jpg"
        }
      },
      slug: "my-project",
      title: "My Project",
      language: :en,
      creator: %{slug: "john-doe"},
      properties: %{name: "my-project"}
    }

    assert Project.__identifier__(project) ==
             %Brando.Content.Identifier{
               cover: "/media/dummy/thumb/8qti51006g6.jpg",
               entry_id: 1,
               id: nil,
               language: :en,
               schema: Project,
               status: :published,
               title: "My Project [1]",
               updated_at: nil,
               url: "/en/project/my-project/john-doe/my-project"
             }
  end
end
