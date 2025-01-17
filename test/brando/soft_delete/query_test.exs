defmodule Brando.SoftDelete.QueryTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Content.Container
  alias Brando.Content.Palette
  alias Brando.Content.Template
  alias Brando.Factory
  alias Brando.Images.Gallery
  alias Brando.Images.Image
  alias Brando.MigrationTest.Profile
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias Brando.Persons.Person
  alias Brando.SoftDelete.Query
  alias Brando.Users.User
  alias Brando.Videos.Video

  test "list_soft_delete_schemas" do
    assert Enum.sort(Query.list_soft_delete_schemas()) == [
             Brando.BlueprintTest.Project,
             Container,
             Brando.Content.Module,
             Palette,
             Template,
             Brando.Files.File,
             Gallery,
             Image,
             Profile,
             Brando.MigrationTest.Project,
             Fragment,
             Page,
             Person,
             User,
             Video
           ]
  end

  test "count_soft_deletions" do
    assert Enum.sort(Query.count_soft_deletions()) == [
             {Brando.BlueprintTest.Project, 0},
             {Container, 0},
             {Brando.Content.Module, 0},
             {Palette, 0},
             {Template, 0},
             {Brando.Files.File, 0},
             {Gallery, 0},
             {Image, 0},
             {Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Fragment, 0},
             {Page, 0},
             {Person, 0},
             {User, 0},
             {Video, 0}
           ]

    sixty_days_in_seconds = -60 * 24 * 3600
    sixty_days_ago = DateTime.add(DateTime.utc_now(), sixty_days_in_seconds, :second)

    Factory.insert(:page,
      deleted_at: sixty_days_ago
    )

    Factory.insert(:image,
      deleted_at: sixty_days_ago
    )

    Factory.insert(:random_user,
      deleted_at: sixty_days_ago
    )

    Factory.insert(:random_user,
      deleted_at: sixty_days_ago
    )

    Factory.insert(:fragment, deleted_at: DateTime.utc_now())

    assert Enum.sort(Query.count_soft_deletions()) == [
             {Brando.BlueprintTest.Project, 0},
             {Container, 0},
             {Brando.Content.Module, 0},
             {Palette, 0},
             {Template, 0},
             {Brando.Files.File, 0},
             {Gallery, 0},
             {Image, 1},
             {Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Fragment, 1},
             {Page, 1},
             {Person, 0},
             {User, 2},
             {Video, 0}
           ]

    deleted_users = Query.list_soft_deleted_entries(User)
    assert Enum.count(deleted_users) == 2

    deleted_entries = Query.list_soft_deleted_entries()
    assert Enum.count(deleted_entries) == 5

    Query.clean_up_soft_deletions()

    assert Enum.sort(Query.count_soft_deletions()) == [
             {Brando.BlueprintTest.Project, 0},
             {Container, 0},
             {Brando.Content.Module, 0},
             {Palette, 0},
             {Template, 0},
             {Brando.Files.File, 0},
             {Gallery, 0},
             {Image, 0},
             {Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Fragment, 1},
             {Page, 0},
             {Person, 0},
             {User, 0},
             {Video, 0}
           ]
  end
end
