defmodule Brando.SoftDelete.QueryTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.SoftDelete.Query

  test "list_soft_delete_schemas" do
    assert Query.list_soft_delete_schemas() == [
             Brando.Pages.Fragment,
             Brando.BlueprintTest.Project,
             Brando.Villain.Module,
             Brando.Image,
             Brando.ImageCategory,
             Brando.Pages.Page,
             Brando.Users.User,
             Brando.ImageSeries
           ]
  end

  test "count_soft_deletions" do
    assert Query.count_soft_deletions() == [
             {Brando.Pages.Fragment, 0},
             {Brando.BlueprintTest.Project, 0},
             {Brando.Villain.Module, 0},
             {Brando.Image, 0},
             {Brando.ImageCategory, 0},
             {Brando.Pages.Page, 0},
             {Brando.Users.User, 0},
             {Brando.ImageSeries, 0}
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

    assert Query.count_soft_deletions() == [
             {Brando.Pages.Fragment, 1},
             {Brando.BlueprintTest.Project, 0},
             {Brando.Villain.Module, 0},
             {Brando.Image, 1},
             {Brando.ImageCategory, 0},
             {Brando.Pages.Page, 1},
             {Brando.Users.User, 2},
             {Brando.ImageSeries, 0}
           ]

    deleted_users = Query.list_soft_deleted_entries(Brando.Users.User)
    assert Enum.count(deleted_users) == 2

    deleted_entries = Query.list_soft_deleted_entries()
    assert Enum.count(deleted_entries) == 5

    Query.clean_up_soft_deletions()

    assert Query.count_soft_deletions() == [
             {Brando.Pages.Fragment, 1},
             {Brando.BlueprintTest.Project, 0},
             {Brando.Villain.Module, 0},
             {Brando.Image, 0},
             {Brando.ImageCategory, 0},
             {Brando.Pages.Page, 0},
             {Brando.Users.User, 0},
             {Brando.ImageSeries, 0}
           ]
  end
end
