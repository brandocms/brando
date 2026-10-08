defmodule BrandoAdmin.MetaPreviewsLiveTest do
  # The Previews tab in an entry's Meta drawer: cards that follow the form,
  # and the Markdown version read from the saved entry when the tab opens.
  use Brando.LiveCase

  setup do
    Brando.Cache.SEO.set()
    :ok
  end

  defp page_with_text! do
    user = Factory.insert(:random_user)

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          code: ~s(<div>{% ref refs.text %}</div>),
          refs: [
            %{name: "text", description: nil, uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "x"}}}
          ],
          vars: []
        }),
        user
      )

    text = %Brando.Villain.Blocks.TextBlock{
      data: %Brando.Villain.Blocks.TextBlock.Data{text: "<p>Reopened in <em>2025</em>.</p>", type: :paragraph}
    }

    block = %Brando.Content.Block{
      type: :module,
      active: true,
      source: Brando.Pages.Page.Blocks,
      module_id: module.id,
      uid: Brando.Utils.generate_uid(),
      creator_id: user.id,
      refs: [%Brando.Content.Ref{name: "text", uid: Brando.Utils.generate_uid(), data: text}]
    }

    Factory.insert(:page,
      title: "Sommerro",
      uri: "sommerro",
      meta_description: "A hotel in the old bathhouse.",
      creator: user,
      entry_blocks: [%Brando.Pages.Page.Blocks{sequence: 0, block: block}]
    )
  end

  test "the cards follow the form and the Markdown version follows the save", %{conn: conn} do
    page = page_with_text!()
    {:ok, view, _html} = live(conn, "/admin/pages/update/#{page.id}")
    render_async(view)

    previews = "[id$='-meta-drawer-previews']"
    assert has_element?(view, "[data-testid=meta-tab-previews]")
    assert view |> element("#{previews} [data-testid=meta-preview-search]") |> render() =~ "A hotel in the old bathhouse."

    view
    |> form("#page_form_form", %{"page" => %{"meta_title" => "Sommerro, a hotel reopened"}})
    |> render_change()

    assert view |> element("#{previews} [data-testid=meta-preview-open-graph]") |> render() =~
             "Sommerro, a hotel reopened"

    assert view |> element("#{previews} [data-testid=meta-preview-x]") |> render() =~ "Sommerro, a hotel reopened"

    # Nothing is read until the tab opens.
    assert view |> element("#{previews} [data-testid=meta-preview-markdown]") |> render() =~ "role=\"status\""

    view |> with_target(previews) |> render_hook("load", %{})

    markdown = view |> element("#{previews} [data-testid=meta-preview-markdown]") |> render()
    assert markdown =~ "/sommerro.md"
    assert markdown =~ "# Sommerro"
    assert markdown =~ "Reopened in *2025*."
  end
end
