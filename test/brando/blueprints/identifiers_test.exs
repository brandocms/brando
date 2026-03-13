defmodule Brando.Blueprint.IdentifiersTest do
  use ExUnit.Case
  alias Brando.Pages.Page
  alias Brando.BlueprintTest.Project
  alias Brando.Content.Var

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
  end

  describe "__identifier_preloads__/0" do
    test "returns empty list when identifier only references direct fields" do
      assert Page.__identifier_preloads__() == []
    end

    test "extracts relation preloads from Liquex identifier template" do
      # Project identifier is "{{ entry.title }} [{{ entry.id }}]" — no relations
      assert Project.__identifier_preloads__() == []
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
