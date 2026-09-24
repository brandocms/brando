defmodule BrandoAdmin.Images.AltTextLiveTest do
  use Brando.LiveCase

  alias Brando.Factory
  alias Brando.Images.AltText
  alias Brando.Images.Image

  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)

  defp insert_image(attrs) do
    image = Factory.insert(:image, Map.merge(%{status: :processed, alt: nil}, attrs))
    target = Path.join(Brando.Tenant.Storage.current_media_root(), AltText.rendition(image))
    File.mkdir_p!(Path.dirname(target))
    File.cp!(@fixture, target)
    image
  end

  test "without an AI provider the page lists the gap and offers nothing to run", %{conn: conn} do
    insert_image(%{path: "images/alt-live/plain.jpg"})

    {:ok, view, _html} = live(conn, "/admin/assets/images/alt-text")

    assert has_element?(view, ".alt-text-panel .workspace-panel-heading span", "1")
    refute has_element?(view, "button[phx-click=describe]")
  end

  test "estimates the cost, describes the images, and saves what is accepted", %{conn: conn} do
    Brando.AIStub.configure(shared: true)
    Brando.AIStub.reply("A lighthouse on a rocky shore")
    first = insert_image(%{path: "images/alt-live/first.jpg"})
    second = insert_image(%{path: "images/alt-live/second.jpg"})

    {:ok, view, _html} = live(conn, "/admin/assets/images/alt-text")

    assert has_element?(view, ".alt-text-estimate", "openai:gpt-4o-mini")
    assert has_element?(view, ".alt-text-estimate", "$")
    view |> element("button[phx-click=describe]") |> render_click()

    # Oban runs inline in tests, so the suggestions are written by now.
    assert has_element?(view, "#suggestion-" <> suggestion_id(first) <> " textarea", "A lighthouse on a rocky shore")
    assert has_element?(view, ".ai-suggestion img.ai-suggestion-thumbnail")
    refute has_element?(view, "button[phx-click=describe]")

    view
    |> form("#suggestion-#{suggestion_id(first)} form", %{"text" => "A red lighthouse"})
    |> render_submit()

    assert Brando.Repo.get!(Image, first.id).alt == "A red lighthouse"

    view |> element(".ai-suggestions button[phx-click=accept_all_suggestions]") |> render_click()
    render_async(view, 5_000)

    assert Brando.Repo.get!(Image, second.id).alt == "A lighthouse on a rocky shore"
    refute has_element?(view, ".ai-suggestions")
  end

  test "the image library links to the page with the count", %{conn: conn} do
    insert_image(%{path: "images/alt-live/linked.jpg"})

    {:ok, view, _html} = live(conn, "/admin/assets/images")
    assert has_element?(view, "[data-testid=alt-text-link]", "1 missing")
  end

  defp suggestion_id(image) do
    Brando.SEO.Suggestions.list_open(to_string(Brando.config(:default_language)), [:alt])
    |> Enum.find(&(&1.entry_id == image.id))
    |> Map.fetch!(:id)
    |> to_string()
  end
end
