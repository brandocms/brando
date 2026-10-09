defmodule BrandoAdmin.ScheduledExpiryLiveTest do
  # The expiry (`unpublish_at`) in the admin: its field in the entry's
  # scheduled publishing drawer, the label in listings and the dashboard's
  # "Expiring soon" panel.
  use Brando.LiveCase

  alias Brando.Pages.Page

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  defp at(days), do: DateTime.utc_now() |> DateTime.add(days, :day) |> DateTime.truncate(:second)

  defp page(user, title, attrs) do
    Factory.insert(
      :page,
      Keyword.merge([title: title, creator: user, status: :published, language: :en, publish_at: at(-30)], attrs)
    )
  end

  defp identifier(page) do
    {:ok, _} = Brando.Content.create_identifier(Page, page)
    page
  end

  describe "the entry form" do
    test "has an Expires field beside Publish at, and refuses an expiry before publishing", %{
      conn: conn,
      current_user: user
    } do
      page = page(user, "Campaign", publish_at: at(2))
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

      drawer = "[id$='-scheduled-publishing-drawer']"
      assert has_element?(view, "#{drawer} input[name='page[publish_at]']")
      assert has_element?(view, "#{drawer} input[name='page[unpublish_at]']")
      assert has_element?(view, "#{drawer} label", "Expires")

      params =
        view
        |> render()
        |> form_params("#page_form_form")
        |> put_in(["page", "unpublish_at"], DateTime.to_iso8601(at(1)))
        |> Map.put("_target", ["page", "unpublish_at"])

      view |> element("#page_form_form") |> render_change(params)
      assert has_element?(view, drawer, "Must be after the publishing date")

      later = at(5)
      params = params |> put_in(["page", "unpublish_at"], DateTime.to_iso8601(later))
      view |> element("#page_form_form") |> render_change(params)
      refute has_element?(view, drawer, "Must be after the publishing date")
    end
  end

  describe "a draft with a publishing date" do
    test "is told the date publishes only a pending entry", %{conn: conn, current_user: user} do
      draft = page(user, "Draft", status: :draft, publish_at: at(2))
      {view, _html} = live_form(conn, "/admin/pages/update/#{draft.id}")
      assert has_element?(view, "[id$='-scheduled-publishing-drawer']", "Only a pending entry is published")

      pending = page(user, "Pending", status: :pending, publish_at: at(2))
      {view, _html} = live_form(conn, "/admin/pages/update/#{pending.id}")
      refute has_element?(view, "[id$='-scheduled-publishing-drawer']", "Only a pending entry is published")
    end
  end

  describe "listings" do
    test "show when a published entry expires, beside its status", %{conn: conn, current_user: user} do
      expiring = page(user, "Summer campaign", unpublish_at: at(3))
      page(user, "Evergreen", [])
      expired = page(user, "Over", status: :disabled, unpublish_at: at(-1))

      {:ok, view, _html} = live(conn, "/admin/pages")

      label = "#list-row-#{expiring.id} [data-testid=listing-expiry]"
      assert has_element?(view, label, "Expires #{BrandoAdmin.Dates.day(expiring.unpublish_at)}")
      assert view |> element(label) |> render() =~ ~s(datetime="#{DateTime.to_iso8601(expiring.unpublish_at)}")
      assert view |> render() |> Floki.parse_document!() |> Floki.find("[data-testid=listing-expiry]") |> length() == 1
      refute has_element?(view, "#list-row-#{expired.id} [data-testid=listing-expiry]")
    end
  end

  describe "the dashboard" do
    test "lists what expires in the next two weeks, soonest first", %{current_user: user} do
      later = page(user, "Job post", unpublish_at: at(10)) |> identifier()
      soon = page(user, "Campaign", unpublish_at: at(2)) |> identifier()
      page(user, "Next month", unpublish_at: at(30)) |> identifier()
      page(user, "Draft", status: :draft, unpublish_at: at(3)) |> identifier()

      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: user)
      panel = html |> Floki.parse_document!() |> Floki.find("[data-testid=dashboard-expiring]")

      assert Floki.find(panel, "h2") |> Floki.text() == "Expiring soon"
      assert Floki.find(panel, ".dashboard-count") |> Floki.text() == "2"

      assert Floki.find(panel, ".dashboard-entry a") |> Enum.map(&Floki.attribute(&1, "href")) == [
               ["/admin/pages/update/#{soon.id}"],
               ["/admin/pages/update/#{later.id}"]
             ]

      # The expiries are not in the scheduled publishing panel
      refute html
             |> Floki.parse_document!()
             |> Floki.find("[aria-labelledby=dashboard-scheduled-heading]")
             |> Floki.text() =~
               "Campaign"
    end

    test "says so when nothing expires", %{current_user: user} do
      html = render_component(BrandoAdmin.Components.Dashboard, id: "dashboard", current_user: user)
      panel = html |> Floki.parse_document!() |> Floki.find("[data-testid=dashboard-expiring]")

      assert Floki.find(panel, ".dashboard-entry") == []
      assert Floki.text(panel) =~ "Nothing expires soon"
    end
  end
end
