defmodule Brando.SoftDelete.QueryTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.SoftDelete.Query

  test "list_soft_delete_schemas" do
    assert Enum.sort(Query.list_soft_delete_schemas()) == [
             Brando.BlueprintTest.Project,
             Brando.Content.Module,
             Brando.Content.Palette,
             Brando.Content.Template,
             Brando.Files.File,
             Brando.Images.Gallery,
             Brando.Images.Image,
             Brando.MigrationTest.Profile,
             Brando.MigrationTest.Project,
             Brando.Pages.Fragment,
             Brando.Pages.Page,
             Brando.Persons.Person,
             Brando.Users.User,
             Brando.Videos.Video
           ]
  end

  test "count_soft_deletions" do
    assert Enum.sort(Query.count_soft_deletions()) == [
             {Brando.BlueprintTest.Project, 0},
             {Brando.Content.Module, 0},
             {Brando.Content.Palette, 0},
             {Brando.Content.Template, 0},
             {Brando.Files.File, 0},
             {Brando.Images.Gallery, 0},
             {Brando.Images.Image, 0},
             {Brando.MigrationTest.Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Brando.Pages.Fragment, 0},
             {Brando.Pages.Page, 0},
             {Brando.Persons.Person, 0},
             {Brando.Users.User, 0},
             {Brando.Videos.Video, 0}
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
             {Brando.Content.Module, 0},
             {Brando.Content.Palette, 0},
             {Brando.Content.Template, 0},
             {Brando.Files.File, 0},
             {Brando.Images.Gallery, 0},
             {Brando.Images.Image, 1},
             {Brando.MigrationTest.Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Brando.Pages.Fragment, 1},
             {Brando.Pages.Page, 1},
             {Brando.Persons.Person, 0},
             {Brando.Users.User, 2},
             {Brando.Videos.Video, 0}
           ]

    deleted_users = Query.list_soft_deleted_entries(Brando.Users.User)
    assert Enum.count(deleted_users) == 2

    deleted_entries = Query.list_soft_deleted_entries()
    assert Enum.count(deleted_entries) == 5

    Query.clean_up_soft_deletions()

    assert Enum.sort(Query.count_soft_deletions()) == [
             {Brando.BlueprintTest.Project, 0},
             {Brando.Content.Module, 0},
             {Brando.Content.Palette, 0},
             {Brando.Content.Template, 0},
             {Brando.Files.File, 0},
             {Brando.Images.Gallery, 0},
             {Brando.Images.Image, 0},
             {Brando.MigrationTest.Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Brando.Pages.Fragment, 1},
             {Brando.Pages.Page, 0},
             {Brando.Persons.Person, 0},
             {Brando.Users.User, 0},
             {Brando.Videos.Video, 0}
           ]
  end
end
