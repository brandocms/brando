defmodule BrandoAdmin.AssistantImageReplacementLiveTest do
  # A connected tool's proposal to replace an image's file, under Assistant →
  # From connected tools: both files side by side with their dimensions, the
  # entries that show the image, linked, a warning when the proportions
  # differ, and once applied, no undo.
  # One at a time with the other proposal tests: ProposalFixtures inserts pages
  # whose URIs concurrent transactions would wait on
  use Brando.LiveCase, async: true, group: :shared_locks

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{InsertBlock, Tools}
  alias Brando.ImageFileFixtures
  alias Brando.Images.Image
  alias Brando.Pages.Page

  setup %{current_user: user} do
    c = Brando.ProposalFixtures.context()
    Map.merge(c, %{user: user})
  end

  # OLD in a block of the Identity page, put there by the admin
  defp place!(c, image) do
    ops = [%InsertBlock{target: {Page, c.identity.id}, module: c.case_module.id, media: %{cover: {:image, image.id}}}]
    {:ok, proposal} = Proposals.propose(ops, c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)
  end

  # As the MCP endpoint calls the tool
  defp propose!(c, old, new) do
    context = %Tools.Context{actor: c.user, origin: :mcp, client: "Claude Code"}

    op = %{
      "op" => "replace_image_file",
      "asset" => %{"kind" => "image", "id" => old.id},
      "with" => %{"kind" => "image", "id" => new.id}
    }

    {:ok, result} = Tools.call("prepare_proposal", %{"summary" => "Better photo", "operations" => [op]}, context)
    result
  end

  test "the review shows both files and the entries that show OLD; apply replaces it and offers no undo", c do
    old = ImageFileFixtures.file_image("harbour", {800, 600})
    new = ImageFileFixtures.file_image("harbour-better", {1600, 1200})
    place!(c, old)

    result = propose!(c, old, new)
    assert result.applicable
    assert result.effects.replaced_images == 1

    {:ok, view, _html} = live(c.conn, "/admin/assistant/connected/#{result.proposal_id}")
    card = "#replacement-#{old.id}"

    assert has_element?(view, card <> " [data-testid=assistant-action-replace-file]")
    assert has_element?(view, card <> " .assistant-replacement-file.is-old img[width='800'][height='600']")
    assert has_element?(view, card <> " .assistant-replacement-file.is-new img[width='1600'][height='1200']")
    assert has_element?(view, card <> " .assistant-replacement-name", Path.basename(old.path))
    assert has_element?(view, card <> " .assistant-replacement-name", Path.basename(new.path))
    assert has_element?(view, card <> " .assistant-replacement-uses a[href='/admin/pages/update/#{c.identity.id}']")

    # Same proportions: no warning
    refute has_element?(view, card <> " .assistant-feedback.is-warning")

    # Shared for review, with no entry to choose: the whole proposal, its files too
    view |> element(".assistant-share button") |> render_click()
    link = view |> element("#assistant-review-link") |> render() |> Floki.parse_fragment!() |> Floki.attribute("value")
    {:ok, shared, _html} = live(c.conn, link |> hd() |> URI.parse() |> Map.get(:path))
    assert has_element?(shared, card <> " .assistant-replacement-file.is-new img[width='1600']")

    view |> element("button.assistant-apply") |> render_click()
    assert has_element?(view, "[data-testid=assistant-receipt-badge]")
    refute has_element?(view, "button.assistant-undo")

    assert Brando.Repo.get!(Image, old.id).path == new.path
    assert Brando.Repo.get(Image, new.id) == nil

    # Applied, the card still shows both files as they were
    {:ok, view, _html} = live(c.conn, "/admin/assistant/connected/#{result.proposal_id}")
    assert has_element?(view, card <> " .assistant-replacement-name", Path.basename(old.path))
    refute has_element?(view, "button.assistant-undo")
  end

  test "differing proportions are warned of; a NEW in use is a problem named in the card", c do
    old = ImageFileFixtures.file_image("harbour", {800, 600})
    wide = ImageFileFixtures.file_image("harbour-wide", {1600, 900})

    result = propose!(c, old, wide)
    {:ok, view, _html} = live(c.conn, "/admin/assistant/connected/#{result.proposal_id}")
    assert has_element?(view, "#replacement-#{old.id} .assistant-feedback.is-warning")
    # No entry shows it
    refute has_element?(view, "#replacement-#{old.id} .assistant-replacement-uses li")

    used = ImageFileFixtures.file_image("harbour-used", {800, 600})
    place!(c, used)
    result = propose!(c, old, used)
    refute result.applicable

    {:ok, view, _html} = live(c.conn, "/admin/assistant/connected/#{result.proposal_id}")
    assert has_element?(view, "#replacement-#{old.id}.has-problems .assistant-problems li")
    assert has_element?(view, ".assistant-feedback-problems a[href='#replacement-#{old.id}']")
    assert has_element?(view, "button.assistant-apply[disabled]")
  end
end
