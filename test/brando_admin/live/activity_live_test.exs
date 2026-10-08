defmodule BrandoAdmin.ActivityLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Pages

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  defp create_page(user, title) do
    {:ok, page} =
      Pages.create_page(
        %{
          title: title,
          uri: "activity-#{System.unique_integer([:positive])}",
          language: "en",
          template: "default.html",
          status: :draft
        },
        user
      )

    page
  end

  test "lists what happened, by day, with the person and the entry", %{conn: conn, current_user: user} do
    page = create_page(user, "Sommerro")
    {:ok, _} = Pages.update_page(page.id, %{title: "Sommerro hotel", meta_description: "By the sea"}, user)

    {:ok, view, _} = live(conn, "/admin/config/activity")

    assert has_element?(view, "h1", "Activity")
    assert has_element?(view, ".activity-day h2", "Today")
    assert has_element?(view, ".activity-row .activity-action", "Created")
    assert has_element?(view, ".activity-row .activity-action", "Updated")
    assert has_element?(view, ".activity-row a.activity-entry", "Sommerro hotel")
    assert has_element?(view, ".activity-row .activity-person-name", user.name)
    assert has_element?(view, ".activity-detail", "Changed SEO description and title")
    assert has_element?(view, ".activity-count", "2 events")
  end

  test "filters by action and by title", %{conn: conn, current_user: user} do
    create_page(user, "Sommerro")
    page = create_page(user, "Villa Tide")
    {:ok, _} = Pages.delete_page(page.id, user)

    {:ok, view, _} = live(conn, "/admin/config/activity")

    view |> form("#activity-filters", %{action: "trashed"}) |> render_change()
    assert_patch(view, "/admin/config/activity?action=trashed")
    assert has_element?(view, ".activity-row .activity-action", "Moved to trash")
    refute has_element?(view, ".activity-row .activity-action", "Created")
    assert has_element?(view, ".activity-row .utils-button", "Open trash")

    {:ok, view, _} = live(conn, "/admin/config/activity?q=sommer")
    assert has_element?(view, ".activity-entry", "Sommerro")
    refute has_element?(view, ".activity-entry", "Villa Tide")
  end

  test "compares a change with the revision before it", %{conn: conn, current_user: user} do
    page = create_page(user, "Sommerro")
    {:ok, _} = Pages.update_page(page.id, %{title: "Sommerro hotel"}, user)

    {:ok, view, _} = live(conn, "/admin/config/activity")

    view |> element(".activity-row button", "Compare") |> render_click()

    assert has_element?(view, "#activity-compare-modal")
    assert render(element(view, "#activity-comparison")) =~ "Sommerro hotel"
  end

  test "an entry deleted for good keeps its title, without a link", %{conn: conn, current_user: user} do
    page = Factory.insert(:page, creator: user, title: "Gone")
    Brando.Repo.delete!(page)
    Brando.Activity.deleted(page, user, false)

    {:ok, view, _} = live(conn, "/admin/config/activity")

    assert has_element?(view, ".activity-entry.is-gone", "Gone")
    refute has_element?(view, "a.activity-entry", "Gone")

    assert has_element?(view, ".activity-action", "Deleted permanently")
  end

  test "a change prepared over MCP names the tool, and the person who approved it", %{conn: conn, current_user: user} do
    page = create_page(user, "Sommerro")

    Brando.Activity.with_source(:mcp, %{"client" => "Claude Code"}, fn ->
      {:ok, _} = Pages.update_page(page.id, %{title: "Sommerro hotel"}, user)
    end)

    {:ok, view, _} = live(conn, "/admin/config/activity")
    assert has_element?(view, ".activity-person.is-source .activity-person-line", "Claude Code")
    assert has_element?(view, ".activity-person.is-source .activity-kind[data-kind=mcp]", "MCP")
    assert has_element?(view, ".activity-person.is-source small", "Approved by #{user.name}")
  end

  # Prepared through the same tools as the Assistant and BrandoMCP, then
  # approved and applied by `user`.
  defp apply_proposal(page, user, origin, client \\ nil) do
    alias Brando.Content.Proposals

    op = %{
      "op" => "set_fields",
      "target" => %{"content_type" => "Brando.Pages.Page", "id" => page.id},
      "fields" => %{"title" => page.title <> " hotel"}
    }

    context = %Proposals.Tools.Context{actor: user, origin: origin, client: client}

    {:ok, %{proposal_id: id, version: version}} =
      Proposals.Tools.call("prepare_proposal", %{"summary" => "Retitle", "operations" => [op]}, context)

    {:ok, _} = Proposals.approve(id, version, user)
    {:ok, _} = Proposals.apply(id, version, user)
    id
  end

  describe "who made a change" do
    setup %{current_user: user} do
      hand = create_page(user, "Sommerro")
      {:ok, _} = Pages.update_page(hand.id, %{meta_description: "By the sea"}, user)
      assistant = apply_proposal(create_page(user, "Villa Tide"), user, :assistant)
      mcp = apply_proposal(create_page(user, "Aker brygge"), user, :mcp, "Claude Code")

      Brando.Activity.with_source(:scheduler, fn ->
        {:ok, _} = Pages.update_page(hand.id, %{status: :published}, user)
      end)

      %{assistant: assistant, mcp: mcp}
    end

    test "agents and jobs have a badge, the approver and, for the approver, a link to the proposal",
         %{conn: conn, current_user: user} = c do
      {:ok, view, _} = live(conn, "/admin/config/activity")

      assistant_row = "#activity-event-#{event_id(c.assistant)}"
      assert has_element?(view, "#{assistant_row} .activity-kind[data-kind=assistant]", "AI")
      assert has_element?(view, "#{assistant_row} .activity-person small", "Approved by #{user.name}")
      assert has_element?(view, ~s(#{assistant_row} a.utils-button[href="/admin/assistant/connected/#{c.assistant}"]))

      mcp_row = "#activity-event-#{event_id(c.mcp)}"
      assert has_element?(view, "#{mcp_row} .activity-person-line", "Claude Code")
      assert has_element?(view, "#{mcp_row} .activity-kind[data-kind=mcp]", "MCP")
      assert has_element?(view, ~s(#{mcp_row} a[href="/admin/assistant/connected/#{c.mcp}"]), "Open proposal")

      assert has_element?(view, ".activity-row .activity-kind[data-kind=task]", "Automatic")

      # A person's own changes have no badge
      assert view |> element("#activity-filters") |> render() =~ "All actors"
      assert length(Regex.scan(~r/class="activity-kind"/, render(view))) == 3
    end

    test "only the person who applied a proposal gets the link to it", %{conn: conn} = c do
      other = Brando.Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      {:ok, view, _} = conn |> log_in_user(other) |> live("/admin/config/activity")

      assert has_element?(view, "#activity-event-#{event_id(c.mcp)} .activity-kind", "MCP")
      refute has_element?(view, ~s(a[href^="/admin/assistant/connected/"]))
    end

    test "filters by kind of actor and by MCP client, in the URL", %{conn: conn} do
      {:ok, view, _} = live(conn, "/admin/config/activity")
      assert has_element?(view, ~s(#activity-filters select[name=actor] option[value="mcp:Claude Code"]))

      view |> form("#activity-filters", %{actor: "assistant"}) |> render_change()
      assert_patch(view, "/admin/config/activity?actor=assistant")
      assert has_element?(view, ".activity-row .activity-entry", "Villa Tide hotel")
      refute has_element?(view, ".activity-row .activity-entry", "Aker brygge hotel")
      assert has_element?(view, ".activity-count", "1 event")

      view |> form("#activity-filters", %{actor: "mcp:Claude Code"}) |> render_change()
      assert_patch(view, "/admin/config/activity?actor=mcp%3AClaude+Code")
      assert has_element?(view, ".activity-row .activity-entry", "Aker brygge hotel")
      refute has_element?(view, ".activity-row .activity-entry", "Villa Tide hotel")

      {:ok, view, _} = live(conn, "/admin/config/activity?actor=task")
      assert has_element?(view, ".activity-row .activity-action", "Published")
      assert has_element?(view, ".activity-count", "1 event")

      {:ok, view, _} = live(conn, "/admin/config/activity?actor=person")
      refute has_element?(view, ".activity-kind")
      assert has_element?(view, ".activity-count", "4 events")
    end
  end

  defp event_id(proposal_id) do
    Brando.Repo.one!(
      from(e in Brando.Activity.Event, where: e.proposal_id == ^proposal_id and e.action == :updated, select: e.id)
    )
  end

  test "editors can't open it without group authorization", %{conn: conn} do
    editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    conn = log_in_user(conn, editor)

    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/activity")
  end
end
