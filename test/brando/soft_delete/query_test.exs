defmodule Brando.SoftDelete.QueryTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.SoftDelete.Query

  test "list_soft_delete_schemas" do
    assert Enum.sort(Query.list_soft_delete_schemas()) == [
             Brando.BlueprintTest.Project,
             Brando.Content.Module,
             Brando.Content.Section,
             Brando.Image,
             Brando.ImageCategory,
             Brando.ImageSeries,
             Brando.MigrationTest.Person,
             Brando.MigrationTest.Profile,
             Brando.MigrationTest.Project,
             Brando.Pages.Fragment,
             Brando.Pages.Page,
             Brando.Users.User
           ]
  end

  test "count_soft_deletions" do
    assert Enum.sort(Query.count_soft_deletions()) == [
             {Brando.BlueprintTest.Project, 0},
             {Brando.Content.Module, 0},
             {Brando.Content.Section, 0},
             {Brando.Image, 0},
             {Brando.ImageCategory, 0},
             {Brando.ImageSeries, 0},
             {Brando.MigrationTest.Person, 0},
             {Brando.MigrationTest.Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Brando.Pages.Fragment, 0},
             {Brando.Pages.Page, 0},
             {Brando.Users.User, 0}
           ]

    Factory.insert(:page,
      deleted_at: Timex.subtract(DateTime.utc_now(), Timex.Duration.from_days(60))
    )

    Factory.insert(:image,
      deleted_at: Timex.subtract(DateTime.utc_now(), Timex.Duration.from_days(60))
    )

    Factory.insert(:random_user,
      deleted_at: Timex.subtract(DateTime.utc_now(), Timex.Duration.from_days(60))
    )

    Factory.insert(:random_user,
      deleted_at: Timex.subtract(DateTime.utc_now(), Timex.Duration.from_days(60))
    )

    Factory.insert(:fragment, deleted_at: DateTime.utc_now())

    assert Enum.sort(Query.count_soft_deletions()) == [
             {Brando.BlueprintTest.Project, 0},
             {Brando.Content.Module, 0},
             {Brando.Content.Section, 0},
             {Brando.Image, 1},
             {Brando.ImageCategory, 0},
             {Brando.ImageSeries, 0},
             {Brando.MigrationTest.Person, 0},
             {Brando.MigrationTest.Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Brando.Pages.Fragment, 1},
             {Brando.Pages.Page, 1},
             {Brando.Users.User, 2}
           ]

    deleted_users = Query.list_soft_deleted_entries(Brando.Users.User)
    assert Enum.count(deleted_users) == 2

    deleted_entries = Query.list_soft_deleted_entries()
    assert Enum.count(deleted_entries) == 5

    Query.clean_up_soft_deletions()

    assert Enum.sort(Query.count_soft_deletions()) == [
             {Brando.BlueprintTest.Project, 0},
             {Brando.Content.Module, 0},
             {Brando.Content.Section, 0},
             {Brando.Image, 0},
             {Brando.ImageCategory, 0},
             {Brando.ImageSeries, 0},
             {Brando.MigrationTest.Person, 0},
             {Brando.MigrationTest.Profile, 0},
             {Brando.MigrationTest.Project, 0},
             {Brando.Pages.Fragment, 1},
             {Brando.Pages.Page, 0},
             {Brando.Users.User, 0}
           ]
  end
end
