defmodule BrandoAdmin.ValidateTargetTest do
  # `validate` passes the field `_target` names to the blocks that read the
  # entry. `_target` comes from the browser, so a name that is not an entry
  # field, or a path that does not fit the entry's data, leaves the blocks
  # alone instead of taking the form down.
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Pages.Page

  setup %{current_user: user} do
    {:ok, page} =
      Brando.Pages.create_page(
        Factory.params_for(:page,
          title: "Stored title",
          vars: [%{key: "size", type: "string", label: "Size", value: "Stored size"}]
        ),
        user
      )

    # A Liquid module reads the fields it names; a HEEx module reads them all.
    liquid = insert_module(user, :liquid, ~S(<h1 class="entry-title">{{ entry.title }}</h1>))
    heex = insert_module(user, :heex, ~S(<p>{@entry.title}</p>))

    insert_block(page, user, liquid, 0)
    insert_block(page, user, heex, 1)

    %{page: page}
  end

  defp insert_module(user, type, code) do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          type: type,
          name: %{"en" => "Title #{type}"},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: code,
          refs: [],
          vars: []
        ),
        user
      )

    module
  end

  defp insert_block(page, user, module, sequence) do
    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks),
          "refs" => []
        },
        user
      )
      |> Repo.insert!()

    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: sequence})
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, ".entry-title")
    view
  end

  defp change(view, target, edit \\ & &1) do
    params =
      view
      |> render()
      |> form_params("#page_form_form")
      |> edit.()
      |> Map.put("_target", target)

    view |> element("#page_form_form") |> render_change(params)
  end

  defp shown_title(view) do
    view |> render() |> Floki.parse_document!() |> Floki.find(".entry-title") |> Floki.text()
  end

  # The entry each block holds, read off the LiveView's component state.
  defp block_entries(view) do
    {components, _, _} = :sys.get_state(view.pid).components

    for {_cid, {BrandoAdmin.Components.Form.Block, _id, %{entry: entry}, _private, _prints}} <- components,
        do: entry
  end

  # The form still works: the blocks hold the entry as it was, and a title
  # typed after the bad event reaches them.
  defp assert_still_syncs(view) do
    assert Process.alive?(view.pid)

    entries = block_entries(view)
    assert length(entries) == 2
    assert Enum.all?(entries, &match?(%Page{title: "Stored title"}, &1))

    change(view, ["page", "title"], &put_in(&1, ["page", "title"], "Typed after"))
    assert shown_title(view) == "Typed after"
  end

  test "a typed title reaches the block that reads it", %{conn: conn, page: page} do
    view = open(conn, page)
    assert shown_title(view) == "Stored title"

    change(view, ["page", "title"], &put_in(&1, ["page", "title"], "Typed title"))

    assert shown_title(view) == "Typed title"
  end

  test "a value in a subform row reaches the blocks that read the entry", %{conn: conn, page: page} do
    view = open(conn, page)
    path = ["page", "vars", "0", "value"]

    change(view, path, &put_in(&1, path, "Typed size"))

    # The HEEx block reads every field; the Liquid one reads only the title.
    values = view |> block_entries() |> Enum.map(fn %{vars: [var]} -> var.value end) |> Enum.sort()
    assert values == ["Stored size", "Typed size"]
  end

  test "a field name with no atom is ignored", %{conn: conn, page: page} do
    view = open(conn, page)

    change(view, ["page", "no_such_field_#{System.unique_integer([:positive])}"])

    assert_still_syncs(view)
  end

  test "a target naming only the entry is ignored", %{conn: conn, page: page} do
    view = open(conn, page)

    change(view, ["page"])

    assert_still_syncs(view)
  end

  test "an index into a field that holds a struct is ignored", %{conn: conn, page: page} do
    view = open(conn, page)

    change(view, ["page", "creator", "0"], &put_in(&1, ["page", "creator"], %{"0" => "x"}))

    assert_still_syncs(view)
  end

  test "an index into a field whose param is a string is ignored", %{conn: conn, page: page} do
    view = open(conn, page)

    change(view, ["page", "title", "0"])

    assert_still_syncs(view)
  end

  test "a key that is no field of the entry is ignored", %{conn: conn, page: page} do
    view = open(conn, page)

    change(view, ["page", "__struct__"], &put_in(&1, ["page", "__struct__"], "Elixir.Brando.Pages.Page"))

    assert_still_syncs(view)
  end
end
