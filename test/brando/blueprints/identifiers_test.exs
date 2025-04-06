defmodule Brando.Blueprint.IdentifiersTest do
  use ExUnit.Case
  alias Brando.Pages.Page
  alias Brando.BlueprintTest.Project

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
