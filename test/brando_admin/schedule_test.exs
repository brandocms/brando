defmodule BrandoAdmin.ScheduleTest do
  # What the calendar and the dashboard read and move (BrandoAdmin.Schedule)
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias BrandoAdmin.Schedule

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    {:ok, user: Factory.insert(:random_user, role: :superuser)}
  end

  defp at(seconds), do: DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.truncate(:second)

  defp scheduled_revision(user, publish_at) do
    {:ok, page} = Pages.create_page(Factory.params_for(:page, title: "Original", vars: []), user)
    {:ok, _} = Pages.update_page(page.id, %{title: "Changed"}, user)

    {:ok, _job} =
      Oban.Testing.with_testing_mode(:manual, fn ->
        Brando.Publisher.schedule_revision(Page, page.id, 0, publish_at, user)
      end)

    page
  end

  test "a scheduled revision moves through the publisher, as the revisions drawer moves it", %{user: user} do
    page = scheduled_revision(user, at(3600))
    assert [item] = Schedule.items(user, at(0), at(86_400), kinds: [:revision])
    assert %{kind: :revision, entry_id: entry_id, revision: 0, movable?: true} = item
    assert entry_id == page.id

    later = at(7200)

    assert {:ok, %{at: ^later}} =
             Oban.Testing.with_testing_mode(:manual, fn -> Schedule.reschedule(user, item, later) end)

    assert [%{at: moved}] = Schedule.items(user, at(0), at(86_400), kinds: [:revision])
    assert DateTime.compare(moved, later) == :eq
  end

  test "a time that has passed, or an item the user may not move, is refused", %{user: user} do
    page = Factory.insert(:page, status: :pending, publish_at: at(3600), creator: user)
    assert [item] = Schedule.items(user, at(0), at(86_400), kinds: [:publish])

    assert {:error, :in_the_past} = Schedule.reschedule(user, item, at(-60))
    assert {:error, :forbidden} = Schedule.reschedule(user, %{item | movable?: false}, at(7200))
    assert Repo.get!(Page, page.id).publish_at == item.at
  end

  test "deleted entries and entries without a plan are left out", %{user: user} do
    Factory.insert(:page, status: :pending, publish_at: at(3600), deleted_at: at(-10))
    Factory.insert(:page, status: :published, publish_at: at(3600))
    Factory.insert(:page, status: :draft, unpublish_at: at(3600))

    assert Schedule.items(user, at(0), at(86_400)) == []
  end
end
