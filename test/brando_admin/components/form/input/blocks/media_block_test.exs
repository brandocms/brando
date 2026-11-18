defmodule BrandoAdmin.Components.Form.Input.Blocks.MediaBlockTest do
  # An empty media ref: in the source it offers a button per media type; in a
  # synchronized translation (`.is-source-locked` on the block field,
  # MediaBlock.css) its note says why there are none. Both are rendered, and
  # the stylesheet shows one of them, so the ref renders the same either way.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Villain.Blocks.MediaBlock, as: Data
  alias BrandoAdmin.Components.Form.Input.Blocks.MediaBlock

  defp render_media_ref do
    ref =
      %Brando.Content.Ref{
        uid: "cover-uid",
        name: "cover",
        data: %Data{type: "media", data: %Data.Data{available_blocks: ["picture", "video"]}}
      }

    ref_form = to_form(Ecto.Changeset.change(ref), as: "block[refs][0]")
    block = to_form(Ecto.Changeset.change(ref.data), as: "block[refs][0][data]")

    render_component(MediaBlock,
      id: "cover-uid-media",
      block: block,
      ref_form: ref_form,
      ref_name: "cover",
      ref_description: "Override image",
      config_open: nil,
      target: nil,
      target_ref: {BrandoAdmin.Components.Form.Block, "block-1"}
    )
  end

  test "an empty media ref explains, for a translation, why it offers no media types" do
    html = render_media_ref()
    {:ok, doc} = Floki.parse_fragment(html)

    assert [note] = Floki.find(doc, ".media-block .empty .media-block-source-note")
    assert Floki.text(note) =~ "No media chosen in the source. Media follows the source; choose it there."

    # The source's controls are still rendered beside it; the stylesheet
    # chooses. The available types round-trip either way.
    assert length(Floki.find(doc, ~s(.media-block .buttons button[phx-value-block]))) == 2
    assert Floki.find(doc, ~s(input[type="hidden"][name$="[available_blocks][]"])) != []
  end
end
