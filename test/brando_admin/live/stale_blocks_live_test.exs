defmodule BrandoAdmin.StaleBlocksLiveTest do
  # Block modules → Blocks on older versions, the module editor's notice, and
  # what an editor with the entry open sees when the blocks are resolved.
  use Brando.LiveCase

  import Brando.EditSessionEditors
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias Brando.Pages.Page

  setup %{current_user: me} do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    c = Brando.ProposalFixtures.context()

    # The Text module is on version 2, which defines a `heading` variable;
    # the Identity page's blocks are on version 1 and still hold `title`.
    module = c.text_module

    Repo.insert!(%Var{module_id: module.id, key: "heading", type: :string, label: %{"en" => "Heading"}, sequence: 0})
    module = module |> Ecto.Changeset.change(version: 2) |> Repo.update!()
    blocks = c.identity |> rows() |> Enum.map(& &1.block)

    for {block, n} <- Enum.with_index(blocks) do
      Repo.insert!(%Var{
        block_id: block.id,
        key: "title",
        type: :string,
        label: %{"en" => "Title"},
        value: "Old title #{n}",
        sequence: 0
      })

      block |> Ecto.Changeset.change(module_version: 1) |> Repo.update!()
    end

    # The Naming page's blocks are current.
    for %{block: block} <- rows(c.naming), do: block |> Ecto.Changeset.change(module_version: 2) |> Repo.update!()

    Map.merge(c, %{me: me, module: module, blocks: blocks})
  end

  defp path(c), do: "/admin/config/content/modules/update/#{c.module.id}/stale-blocks"
  defp version(block), do: Repo.get!(Block, block.id).module_version
  defp var(block, key), do: Repo.one(from(v in Var, where: v.block_id == ^block.id and v.key == ^key))

  test "the module editor says how many blocks are behind and links to resolving them", %{conn: conn} = c do
    {:ok, view, _} = live(conn, "/admin/config/content/modules/update/#{c.module.id}")

    assert has_element?(view, ".stale-blocks-notice", "3 blocks on older versions")
    assert has_element?(view, ~s(.stale-blocks-notice a[href="#{path(c)}"]))
  end

  test "the overview lists the modules with blocks behind", %{conn: conn} = c do
    {:ok, view, _} = live(conn, "/admin/config/content/modules/stale-blocks")

    assert has_element?(view, ~s(article[data-module="#{c.module.uid}"]), "3 blocks on older versions than 2")
    assert has_element?(view, ~s(article[data-module="#{c.module.uid}"] a[href="#{path(c)}"]))
  end

  test "lists each block's entry, version and leftovers with their values", %{conn: conn} = c do
    {:ok, view, _} = live(conn, path(c))
    [first | _] = c.blocks

    assert has_element?(view, ~s([data-leftover="var:title"] h3), "title")
    assert has_element?(view, "#stale-block-#{first.id} .stale-block-entry a", "Identity")
    assert has_element?(view, "#stale-block-#{first.id} .stale-block-chip", "Version 1")
    assert has_element?(view, "#stale-block-#{first.id} .stale-block-value", "Old title 0")
    # the mapping target is the shared select, with the compatible var offered
    assert has_element?(view, ~s(select.admin-select[name="bulk[var:title]"] option[value="map:heading"]))
  end

  test "drops a leftover in every block after a review, and the blocks are current", %{conn: conn} = c do
    {:ok, view, _} = live(conn, path(c))

    view |> form("#stale-blocks-form", %{"bulk" => %{"var:title" => "drop"}}) |> render_change()
    view |> form("#stale-blocks-form") |> render_submit()

    assert has_element?(view, "#stale-blocks-review", "Drop title in 3 blocks")
    assert has_element?(view, ".stale-blocks-lost li", "Old title 0")
    assert has_element?(view, "#stale-blocks-resolve[data-confirm-destructive]")

    view |> element("#stale-blocks-resolve") |> render_click()

    assert has_element?(view, ".stale-blocks-done", "Brought 3 blocks up to date.")
    assert has_element?(view, ".stale-blocks-empty", "All blocks of Text are on version 2.")

    for block <- c.blocks do
      assert version(block) == 2
      assert var(block, "title") == nil
    end

    # Activity says who did it and what was dropped, on the entry and the module
    {:ok, activity, _} = live(conn, "/admin/config/activity")
    html = render(activity)
    assert html =~ "Brought 3 Text blocks up to date"
    assert html =~ "Dropped title"
  end

  test "a block can say otherwise than the rest", %{conn: conn} = c do
    [first, second, third] = c.blocks
    {:ok, view, _} = live(conn, path(c))

    view
    |> form("#stale-blocks-form", %{
      "bulk" => %{"var:title" => "drop"},
      "block" => %{"#{second.id}" => %{"var:title" => "map:heading"}, "#{third.id}" => %{"var:title" => "keep"}}
    })
    |> render_change()

    view |> form("#stale-blocks-form") |> render_submit()
    view |> element("#stale-blocks-resolve") |> render_click()

    assert var(first, "title") == nil
    assert var(second, "heading").value == "Old title 1"
    assert var(third, "title")
    assert version(third) == 1
    assert has_element?(view, "#stale-block-#{third.id}")
    refute has_element?(view, "#stale-block-#{first.id}")
  end

  test "a resolve is refused when the blocks changed after the review", %{conn: conn} = c do
    [first | _] = c.blocks
    {:ok, view, _} = live(conn, path(c))

    view |> form("#stale-blocks-form", %{"bulk" => %{"var:title" => "drop"}}) |> render_change()
    view |> form("#stale-blocks-form") |> render_submit()
    Repo.update_all(from(v in Var, where: v.block_id == ^first.id and v.key == "title"), set: [value: "Typed since"])
    view |> element("#stale-blocks-resolve") |> render_click()

    assert has_element?(view, ".utils-feedback.error", "changed after you reviewed them")
    assert var(first, "title").value == "Typed since"
  end

  test "an editor with the entry open moves onto the resolved rows, keeping its unsaved work", %{conn: conn} = c do
    [first | _] = c.blocks
    {view, _html} = live_form(conn, "/admin/pages/update/#{c.identity.id}")
    await_selector(view, "[data-block-uid]")
    type(view, first.uid, "<p>Typed before the resolve</p>")

    # the block's variable as the editor shows it: its label and value
    shown_var = fn ->
      form = view |> render() |> Floki.parse_document!() |> Floki.find("#entry_block_form-#{first.uid}")
      label = form |> Floki.find(".block-var label, .var label, label") |> Enum.map(&Floki.text/1) |> Enum.join(" ")

      value =
        form |> Floki.raw_html() |> form_params_from_html() |> get_in(["entry_block", "block", "vars", "0", "value"])

      {label =~ "Heading", label =~ "Title", value}
    end

    assert {false, true, "Old title 0"} = shown_var.()

    assert {:ok, _} =
             Brando.Content.StaleBlocks.apply(c.module, %{{:var, "title"} => {:map, "heading"}}, c.user)

    await(fn -> shown_var.() == {true, false, "Old title 0"} end)
    assert shown_text(view, first.uid) == "<p>Typed before the resolve</p>"

    # its save keeps the resolved rows and writes the typing
    view |> with_target(cid_of(view, "#page_form-el")) |> render_hook("save_redirect_target", %{})
    view |> form("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> form("#page_form_form") |> render_submit()

    await(fn ->
      Enum.any?(rows(c.identity), &(hd(&1.block.refs).data.data.text == "<p>Typed before the resolve</p>"))
    end)

    assert var(first, "title") == nil
    assert var(first, "heading").value == "Old title 0"
    assert version(first) == 2
    assert Repo.aggregate(from(b in Block, where: b.uid == ^first.uid), :count) == 1
    assert Repo.get!(Page, c.identity.id)
  end

  defp form_params_from_html(html), do: form_params(html, "form")

  defp cid_of(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("[data-phx-component]")
    |> Enum.filter(&(Floki.find(&1, selector) != []))
    |> Enum.min_by(&(&1 |> Floki.raw_html() |> byte_size()))
    |> Floki.attribute("data-phx-component")
    |> hd()
    |> String.to_integer()
  end
end
