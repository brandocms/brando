defmodule BrandoAdmin.Images.AltTextLiveTest do
  use Brando.LiveCase

  alias Brando.Factory
  alias Brando.Images.AltText
  alias Brando.Images.Image

  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)

  defp insert_image(attrs) do
    base = Path.rootname(attrs.path)
    sizes = Map.new(~w(thumb small medium large xlarge), &{&1, "#{base}/#{&1}.jpg"})
    image = Factory.insert(:image, Map.merge(%{status: :processed, alt: nil, sizes: sizes}, attrs))
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

  test "estimates the cost, describes the images in every language, and saves what is accepted", %{conn: conn} do
    Brando.AIStub.configure(shared: true)
    Brando.AIStub.reply(~s({"en": "A lighthouse on a rocky shore", "no": "Et fyr på en steinete strand"}))
    first = insert_image(%{path: "images/alt-live/first.jpg"})
    second = insert_image(%{path: "images/alt-live/second.jpg"})

    {:ok, view, _html} = live(conn, "/admin/assets/images/alt-text")

    assert has_element?(view, ".alt-text-estimate", "openai:gpt-4o-mini")
    assert has_element?(view, ".alt-text-estimate", "$")
    view |> element("button[phx-click=describe]") |> render_click()

    # Oban runs inline in tests, so the suggestions are written by now.
    id = suggestion_id(first)
    assert has_element?(view, "#suggestion-text-#{id}-en", "A lighthouse on a rocky shore")
    assert has_element?(view, "#suggestion-text-#{id}-no", "Et fyr på en steinete strand")
    assert has_element?(view, ".ai-suggestion img.ai-suggestion-thumbnail")
    refute has_element?(view, "button[phx-click=describe]")

    view
    |> form("#suggestion-#{id} form", %{"values" => %{"en" => "A red lighthouse", "no" => "Et rødt fyr"}})
    |> render_submit()

    assert Brando.Repo.get!(Image, first.id).alt == %{"en" => "A red lighthouse", "no" => "Et rødt fyr"}

    view |> element(".ai-suggestions button[phx-click=accept_all_suggestions]") |> render_click()
    render_async(view, 5_000)

    assert Brando.Repo.get!(Image, second.id).alt == %{
             "en" => "A lighthouse on a rocky shore",
             "no" => "Et fyr på en steinete strand"
           }

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
