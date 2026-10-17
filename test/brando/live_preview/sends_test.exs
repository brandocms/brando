defmodule Brando.LivePreview.SendsTest do
  use Brando.ConnCase

  alias Brando.LivePreview
  alias Brando.Pages.Page
  alias Phoenix.Socket.Broadcast

  setup do
    entry = %Page{title: "Unsaved title", language: :en, entry_blocks: []} |> Map.put(:key, "about")
    changeset = Ecto.Changeset.change(entry)
    {:ok, key} = LivePreview.initialize(Page, changeset, %{}, :listing)
    on_exit(fn -> LivePreview.cleanup_cache(key) end)
    Brando.endpoint().subscribe("live_preview:#{key}")
    {:ok, key: key, changeset: changeset}
  end

  test "a render the iframe already shows is not sent again", %{key: key, changeset: changeset} do
    assert ^key = LivePreview.update(Page, changeset, key)
    refute_received %Broadcast{}

    changed = Ecto.Changeset.put_change(changeset, :title, "Another edit")
    LivePreview.invalidate_var(key, :employees)
    assert ^key = LivePreview.update(Page, changed, key)
    assert_received %Broadcast{event: "update", payload: %{html: html, v: version}}
    assert html =~ "Another edit"
    assert {:ok, document} = LivePreview.get_cache(key)
    assert document =~ "Another edit"
    assert version == LivePreview.page_state(key).generation

    assert ^key = LivePreview.update(Page, changed, key)
    refute_received %Broadcast{}

    # A reload is what mounts new media, so it always goes out
    assert ^key = LivePreview.reload(Page, changed, key)
    assert_received %Broadcast{event: "reload"}
  end

  test "an update sends only <main>, so a rerender of the same page still goes out", c do
    changed = Ecto.Changeset.put_change(c.changeset, :title, "Another edit")
    LivePreview.invalidate_var(c.key, :employees)
    assert c.key == LivePreview.update(Page, changed, c.key)
    assert_received %Broadcast{event: "update"}

    assert c.key == LivePreview.rerender(Page, changed, c.key)
    assert_received %Broadcast{event: "rerender", payload: %{html: html}}
    assert html =~ "<head"

    assert c.key == LivePreview.rerender(Page, changed, c.key)
    assert c.key == LivePreview.update(Page, changed, c.key)
    refute_received %Broadcast{}
  end

  test "a block patch or an unsent cache refresh makes the next render go out", %{key: key, changeset: changeset} do
    LivePreview.broadcast(key, "update_block", %{uid: "B1", rendered_html: "<p>x</p>", has_children: false})
    assert_received %Broadcast{event: "update_block"}
    assert ^key = LivePreview.update(Page, changeset, key)
    assert_received %Broadcast{event: "update"}

    assert ^key = LivePreview.update_cache(key, Page, changeset)
    refute_received %Broadcast{}
    assert ^key = LivePreview.update(Page, changeset, key)
    assert_received %Broadcast{event: "update"}
  end

  # Patches are not in the cache; a render, made from the whole form, is.
  test "block patches are counted until the next render", %{key: key, changeset: changeset} do
    patch = %{uid: "B1", rendered_html: "<p>x</p>", has_children: false}

    LivePreview.broadcast(key, "update_block", patch)
    LivePreview.broadcast(key, "update_block", patch)
    assert_received %Broadcast{event: "update_block", payload: %{p: 1}}
    assert_received %Broadcast{event: "update_block", payload: %{p: 2}}
    assert %{patches: 2, generation: generation} = LivePreview.page_state(key)

    assert ^key = LivePreview.update(Page, changeset, key)
    assert LivePreview.page_state(key) == %{patches: 0, generation: generation + 1}
    LivePreview.broadcast(key, "update_block", patch)
    assert_received %Broadcast{event: "update_block", payload: %{p: 1}}
  end
end
