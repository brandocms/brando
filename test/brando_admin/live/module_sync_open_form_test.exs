defmodule BrandoAdmin.ModuleSyncOpenFormTest do
  # An editor has a page open while an admin saves a module the page's blocks
  # use. The module save syncs the blocks in the database (a new var, the
  # ref's settings); the open form still holds them as it loaded them. Its
  # next save syncs the blocks it writes too, so it keeps what the module
  # save did and the editor's edits (#3901).
  use Brando.LiveCase

  import Brando.EditSessionEditors
  import Ecto.Query, only: [from: 2]

  alias Brando.Content
  alias Brando.Content.Block

  setup %{current_user: me} do
    c = Brando.ProposalFixtures.context()
    stamp(c.text_module)
    Map.put(c, :me, me)
  end

  # The fixture inserts its blocks unstamped; a block saved through Brando
  # holds the version of the module it was synced with
  defp stamp(module) do
    module = Repo.reload!(module)
    Repo.update_all(from(b in Block, where: b.module_id == ^module.id), set: [module_version: module.version])
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  # "Save and continue editing": two submits, the first collects the blocks
  defp save(view) do
    view |> with_target(cid_of(view, "#page_form-el")) |> render_hook("save_redirect_target", %{})
    view |> form("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> form("#page_form_form") |> render_submit()
  end

  # An admin saves the module: a new var, and the body ref becomes a lede
  defp save_module(module, user) do
    module = Repo.preload(module, [:vars, :refs], force: true)
    [body] = module.refs

    params = %{
      vars: [%{type: "string", key: "heading", label: "Heading", value: "Default heading"}],
      refs: [%{id: body.id, name: "body", data: %{type: "text", data: %{text: "Default body", type: "lede"}}}]
    }

    {:ok, module} = Content.update_module(module, params, user)
    module
  end

  defp saved_block(uid), do: Repo.one!(from(b in Block, where: b.uid == ^uid, preload: [:vars, :refs]))

  test "saves of blocks the form holds as they are saved sync nothing", c do
    # The blocks are from before version tracking, and the module's body is a
    # lede the blocks were never synced with
    Repo.update_all(from(b in Block, where: b.module_id == ^c.text_module.id), set: [module_version: nil])
    [body] = Repo.preload(c.text_module, :refs, force: true).refs
    lede = %{body.data | data: %{body.data.data | type: :lede}}
    body |> Ecto.Changeset.change(data: lede) |> Repo.update!()

    [first | _] = Enum.map(rows(c.identity), & &1.block.uid)
    view = open(c.conn, c.identity)

    for text <- ["<p>First save</p>", "<p>Second save</p>"] do
      type(view, first, text)
      save(view)
      await(fn -> hd(saved_block(first).refs).data.data.text == text end)
    end

    block = saved_block(first)
    assert hd(block.refs).data.data.type == :paragraph
    assert block.vars == []
    assert block.module_version == nil
  end

  test "a save after a module save keeps the module's var and settings and the editor's edit", c do
    [first, second | _] = Enum.map(rows(c.identity), & &1.block.uid)
    view = open(c.conn, c.identity)
    type(view, first, "<p>Edited while the module changed</p>")

    module = save_module(c.text_module, c.user)
    assert Enum.map(saved_block(first).vars, & &1.key) == ["heading"]

    save(view)
    await(fn -> hd(saved_block(first).refs).data.data.text == "<p>Edited while the module changed</p>" end)

    block = saved_block(first)
    assert Enum.map(block.vars, & &1.key) == ["heading"]
    assert hd(block.refs).data.data.type == :lede
    assert block.module_version == module.version

    # A block the editor did not touch is as the module save left it
    untouched = saved_block(second)
    assert Enum.map(untouched.vars, & &1.key) == ["heading"]
    assert hd(untouched.refs).data.data.type == :lede

    # The form holds the synced block: the new var is there to fill in
    [heading] = block.vars
    heading_id = to_string(heading.id)

    await(fn ->
      vars = view |> render() |> form_params("#entry_block_form-#{first}") |> get_in(["entry_block", "block", "vars"])
      Enum.any?(Map.values(vars || %{}), &(&1["id"] == heading_id))
    end)
  end
end
