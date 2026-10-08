defmodule BrandoAdmin.CalendarLiveTest do
  # The calendar (`/admin/calendar`): what is planned for entries, by day, in
  # the site's time zone; only what the user may read; and moving an item to
  # another day, keeping its time, only where the user may.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Pages.Page

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  # A day well inside the month after this one, at 09:30 in the site's time zone
  defp day(offset \\ 0) do
    date = Brando.timezone() |> DateTime.now!() |> DateTime.to_date() |> Date.beginning_of_month() |> Date.shift(month: 1)
    Date.add(date, 10 + offset)
  end

  defp at(date, time \\ ~T[09:30:00]),
    do: date |> DateTime.new!(time, Brando.timezone()) |> DateTime.shift_zone!("Etc/UTC")

  defp page(user, title, attrs) do
    Factory.insert(:page, Keyword.merge([title: title, creator: user, language: :en, publish_at: nil], attrs))
  end

  defp month_path(date), do: "/admin/calendar?date=#{date}"

  defp item_id(kind, page), do: "#{kind}-pages_page-#{page.id}"

  describe "showing" do
    test "publishing, expiries and scheduled revisions on their days, in the site's time zone", %{
      conn: conn,
      current_user: user
    } do
      scheduled = page(user, "Autumn campaign", status: :pending, publish_at: at(day()))

      expiring =
        page(user, "Job post", status: :published, publish_at: at(day(-5)), unpublish_at: at(day(2), ~T[23:30:00]))

      page(user, "Already out", status: :published, publish_at: at(day()))

      {:ok, original} = Brando.Pages.create_page(Factory.params_for(:page, title: "Revision source", vars: []), user)
      {:ok, _} = Brando.Pages.update_page(original.id, %{title: "Revision source, changed"}, user)

      {:ok, _job} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          Brando.Publisher.schedule_revision(Page, original.id, 0, at(day(3), ~T[07:00:00]), user)
        end)

      {:ok, view, _html} = live(conn, month_path(day()))

      assert has_element?(
               view,
               "#calendar-title",
               String.capitalize(Brando.Utils.Datetime.get_month_name(day().month, "en"))
             )

      publish = "#calendar-day-#{day()} #calendar-item-#{item_id(:publish, scheduled)}"
      assert has_element?(view, publish <> " .calendar-item-time", "09:30")
      assert has_element?(view, publish <> " a[href='/admin/pages/update/#{scheduled.id}']", "Autumn campaign")

      # 23:30 local is the next day in UTC, and stays on its local day
      assert has_element?(
               view,
               "#calendar-day-#{day(2)} #calendar-item-#{item_id(:expire, expiring)} .calendar-item-time",
               "23:30"
             )

      assert has_element?(
               view,
               "#calendar-day-#{day(3)} #calendar-item-revision-pages_page-#{original.id}-0 .calendar-item-time",
               "07:00"
             )

      # A published entry has nothing planned
      refute render(view) =~ "Already out"
      assert has_element?(view, "#calendar-day-#{day()}[aria-label*='1 item']")
    end

    test "a week, and the arrows step by the view", %{conn: conn, current_user: user} do
      scheduled = page(user, "Autumn campaign", status: :pending, publish_at: at(day()))
      monday = Date.beginning_of_week(day())

      {:ok, view, _html} = live(conn, "/admin/calendar?view=week&date=#{day()}")

      assert view
             |> element("#calendar .calendar-days")
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find("li.calendar-day")
             |> length() == 7

      assert has_element?(view, "#calendar-day-#{monday}")
      assert has_element?(view, "#calendar-item-#{item_id(:publish, scheduled)} .calendar-item-meta", "Page")
      assert has_element?(view, "#calendar-view-week[aria-current=page]")

      view |> element("#calendar-next") |> render_click()
      assert_patch(view, "/admin/calendar?view=week&date=#{Date.add(day(), 7)}")
      assert has_element?(view, "#calendar-day-#{Date.add(monday, 7)}")
      assert has_element?(view, "#calendar-empty")
    end

    test "the type filter keeps to one content type, in the URL", %{conn: conn, current_user: user} do
      page(user, "Autumn campaign", status: :pending, publish_at: at(day()))
      {:ok, view, _html} = live(conn, month_path(day()))

      view |> element("#calendar-filter") |> render_change(%{"type" => "pages.page"})
      assert_patch(view, "/admin/calendar?date=#{day()}&type=pages.page")
      assert has_element?(view, "#calendar-type option[value='pages.page'][selected]")
      assert render(view) =~ "Autumn campaign"

      # A type the user may not read, or that has no schedule, is not a filter
      {:ok, view, _html} = live(conn, month_path(day()) <> "&type=users.user")
      refute has_element?(view, "#calendar-type option[selected]")
      assert render(view) =~ "Autumn campaign"
    end

    test "the sidebar has the calendar after Dashboard and Search", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/calendar")
      nav = find_live_child(view, "brando-nav")
      assert has_element?(nav, ".navigation-section:first-child dl:nth-of-type(3) a[href='/admin/calendar']")
    end
  end

  describe "moving" do
    test "a dropped item asks first, then moves to the day at the same time, as the form would", %{
      conn: conn,
      current_user: user
    } do
      scheduled = page(user, "Autumn campaign", status: :pending, publish_at: at(day()))
      {:ok, view, _html} = live(conn, month_path(day()))
      id = item_id(:publish, scheduled)

      assert has_element?(view, "#calendar-item-#{id}[draggable=true]")

      reply = render_hook(view, "describe_move", %{"item" => id, "date" => Date.to_iso8601(day(4))})
      assert reply =~ "calendar-workspace"
      assert_reply(view, %{title: "Move “Autumn campaign”?", message: message, confirm: "Move"})
      assert message =~ "Publishing moves from"

      render_hook(view, "move", %{"item" => id, "date" => Date.to_iso8601(day(4))})

      moved = Repo.get!(Page, scheduled.id)
      assert moved.publish_at == at(day(4))
      assert moved.status == :pending
      assert has_element?(view, "#calendar-day-#{day(4)} #calendar-item-#{id}")
      refute has_element?(view, "#calendar-day-#{day()} #calendar-item-#{id}")

      # The same save as the form's: Activity has it, as an update by this user
      assert [%{action: :updated, user_id: user_id}] =
               Repo.all(from e in Brando.Activity.Event, where: e.entry_id == ^scheduled.id and e.action == :updated)

      assert user_id == user.id
    end

    test "Move to… opens a dialog with the day, which moves the expiry", %{conn: conn, current_user: user} do
      expiring = page(user, "Job post", status: :published, publish_at: at(day(-5)), unpublish_at: at(day()))
      {:ok, view, _html} = live(conn, month_path(day()))
      id = item_id(:expire, expiring)

      view |> element("#calendar-item-#{id} .calendar-item-move") |> render_click()
      assert has_element?(view, "#calendar-move #calendar-move-date[value='#{day()}']")

      view |> element("#calendar-move-form") |> render_change(%{"item" => id, "date" => Date.to_iso8601(day(6))})
      assert has_element?(view, "#calendar-move-summary", "The expiry moves from")

      view |> element("#calendar-move-form") |> render_submit(%{"item" => id, "date" => Date.to_iso8601(day(6))})

      refute has_element?(view, "#calendar-move")
      assert Repo.get!(Page, expiring.id).unpublish_at == at(day(6))
    end

    @tag :capture_log
    test "a move the entry refuses leaves it, and says why", %{conn: conn, current_user: user} do
      expiring = page(user, "Job post", status: :pending, publish_at: at(day(1)), unpublish_at: at(day(4)))
      {:ok, view, _html} = live(conn, month_path(day()))

      # Before its publishing date
      render_hook(view, "move", %{"item" => item_id(:expire, expiring), "date" => Date.to_iso8601(day())})

      assert_push_event(view, "b:alert", %{type: "error", message: "Must be after the publishing date"})
      assert Repo.get!(Page, expiring.id).unpublish_at == at(day(4))
    end
  end

  describe "with group authorization" do
    setup do
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      owner = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, _} = Migration.run()

      scheduled = page(owner, "Autumn campaign", status: :pending, publish_at: at(day()))
      expiring = page(owner, "Job post", status: :published, publish_at: at(day(-5)), unpublish_at: at(day(1)))
      %{scope: Scope.standalone(owner), scheduled: scheduled, expiring: expiring}
    end

    defp member(c, keys) do
      user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      {:ok, group} = Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, keys)
      {:ok, :ok} = Groups.add_member(c.scope, group.id, user.id)
      log_in_user(Phoenix.ConnTest.build_conn(), user)
    end

    test "without read access the calendar is empty", c do
      conn = member(c, ~w(brando.admin.access))
      {:ok, view, _html} = live(conn, month_path(day()))

      refute render(view) =~ "Autumn campaign"
      refute has_element?(view, "#calendar-type option[value='pages.page']")
    end

    test "reading shows the items without a link or a way to move them", c do
      conn = member(c, ~w(brando.admin.access brando.pages.read))
      {:ok, view, _html} = live(conn, month_path(day()))
      id = item_id(:publish, c.scheduled)

      assert has_element?(view, "#calendar-item-#{id} .calendar-item-title", "Autumn campaign")
      refute has_element?(view, "#calendar-item-#{id} a")
      refute has_element?(view, "#calendar-item-#{id}[draggable]")
      refute has_element?(view, "#calendar-item-#{id} .calendar-item-move")

      # Asking anyway changes nothing
      render_hook(view, "move", %{"item" => id, "date" => Date.to_iso8601(day(3))})
      assert Repo.get!(Page, c.scheduled.id).publish_at == at(day())
    end

    test "scheduling moves publishing; an expiry also takes the right to publish", c do
      conn = member(c, ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.schedule))
      {:ok, view, _html} = live(conn, month_path(day()))

      assert has_element?(view, "#calendar-item-#{item_id(:publish, c.scheduled)} .calendar-item-move")
      refute has_element?(view, "#calendar-item-#{item_id(:expire, c.expiring)} .calendar-item-move")

      render_hook(view, "move", %{"item" => item_id(:expire, c.expiring), "date" => Date.to_iso8601(day(3))})
      assert Repo.get!(Page, c.expiring.id).unpublish_at == at(day(1))

      conn =
        member(
          c,
          ~w(brando.admin.access brando.pages.read brando.pages.update brando.pages.schedule brando.pages.publish)
        )

      {:ok, view, _html} = live(conn, month_path(day()))

      render_hook(view, "move", %{"item" => item_id(:expire, c.expiring), "date" => Date.to_iso8601(day(3))})
      assert Repo.get!(Page, c.expiring.id).unpublish_at == at(day(3))
    end
  end
end
