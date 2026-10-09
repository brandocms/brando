defmodule BrandoAdmin.AltTextSuggestionLiveTest do
  # "Suggest alt text" on an image's own form: the reply waits under the
  # field, one text per language, and reaches the alt text only when the
  # editor accepts it. The model is a stub.
  use Brando.LiveCase

  @fixture Path.expand("../../fixtures/sample.jpg", __DIR__)

  setup do
    Brando.AIStub.configure()

    sizes = Map.new(~w(thumb small medium large xlarge), &{&1, "images/alt-suggestion/#{&1}.jpg"})
    image = Factory.insert(:image, status: :processed, alt: nil, path: "images/alt-suggestion/a.jpg", sizes: sizes)

    target = Path.join(Brando.Tenant.Storage.current_media_root(), Brando.Images.AltText.rendition(image))
    File.mkdir_p!(Path.dirname(target))
    File.cp!(@fixture, target)

    %{image: image}
  end

  defp panel(image), do: "#image_alt-#{image.id}-alt-suggestion"

  defp alt(view, language),
    do: view |> render() |> form_params("#image_form_form") |> get_in(["image", "alt", language])

  test "the suggestion is reviewed per language before it reaches the alt text", %{conn: conn, image: image} do
    {view, _html} = live_form(conn, "/admin/assets/images/update/#{image.id}", "image_form")
    Brando.AIStub.reply(~s({"en": "Two ferries at dusk", "no": "To ferjer i skumringen"}))

    view |> element("button[phx-click='suggest_entry_alt_text']") |> render_click()
    await_selector(view, "#{panel(image)} .ai-proposal[data-status='ready']")

    # Shown, not written
    assert has_element?(view, "#{panel(image)} textarea[lang='en']", "Two ferries at dusk")
    assert has_element?(view, "#{panel(image)} textarea[lang='no']", "To ferjer i skumringen")
    assert alt(view, "en") in [nil, ""]

    # Edited, then accepted
    view |> element("#{panel(image)} textarea[lang='en']") |> render_blur(%{"value" => "Two ferries leaving at dusk"})
    view |> element("#{panel(image)} button", "Accept") |> render_click()
    settle(view)

    assert alt(view, "en") == "Two ferries leaving at dusk"
    assert alt(view, "no") == "To ferjer i skumringen"
    refute has_element?(view, "#{panel(image)} .ai-proposal")
  end

  test "discarded, the alt text is as it was", %{conn: conn, image: image} do
    {view, _html} = live_form(conn, "/admin/assets/images/update/#{image.id}", "image_form")
    Brando.AIStub.reply(~s({"en": "Two ferries", "no": "To ferjer"}))

    view |> element("button[phx-click='suggest_entry_alt_text']") |> render_click()
    await_selector(view, "#{panel(image)} .ai-proposal[data-status='ready']")
    view |> element("#{panel(image)} button", "Discard") |> render_click()

    refute has_element?(view, "#{panel(image)} .ai-proposal")
    assert alt(view, "en") in [nil, ""]
  end

  test "asks only for the languages without text in the form, and keeps what is typed", %{conn: conn, image: image} do
    {view, _html} = live_form(conn, "/admin/assets/images/update/#{image.id}", "image_form")
    test = self()

    Brando.AIStub.reply(fn prompt ->
      send(test, {:prompt, prompt})
      ~s({"no": "To ferjer"})
    end)

    # Typed, not saved
    view |> form("#image_form_form") |> render_change(%{"image" => %{"alt" => %{"en" => "My own", "no" => ""}}})

    view |> element("button[phx-click='suggest_entry_alt_text']") |> render_click()
    await_selector(view, "#{panel(image)} .ai-proposal[data-status='ready']")

    assert_received {:prompt, prompt}
    assert prompt =~ ~s["no" (Norsk)]
    refute prompt =~ ~s["en" (English)]
    refute has_element?(view, "#{panel(image)} textarea[lang='en']")

    view |> element("#{panel(image)} button", "Accept") |> render_click()
    settle(view)

    assert alt(view, "en") == "My own"
    assert alt(view, "no") == "To ferjer"
  end
end
