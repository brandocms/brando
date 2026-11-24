defmodule Brando.Content.SaveSyncsBlocksTest do
  # An entry save brings the blocks it writes up to their modules' current
  # versions (#3901). Each save here is the form's: the entry's blocks as the
  # form loaded them, a changeset per entry block from the block field's
  # params, written through the context's update.
  use Brando.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Brando.Content
  alias Brando.Content.Block
  alias Brando.Content.Blocks
  alias Brando.Pages.Page

  setup do
    Brando.ProposalFixtures.context()
  end

  # The fixtures insert their blocks unstamped; a block saved through Brando
  # holds the version of the module it was synced with
  defp stamp(module) do
    module = Repo.reload!(module)
    Repo.update_all(from(b in Block, where: b.module_id == ^module.id), set: [module_version: module.version])
  end

  defp loaded(page) do
    Page
    |> Repo.get!(page.id)
    |> Repo.preload(Brando.Content.BlockPreloads.for_schema(Page), force: true)
  end

  # The form's save of `page` as it loaded it: `edits` sets the text of a
  # block's text ref by uid; other blocks are sent as their ids, as the
  # block field sends a block it has no change for.
  defp form_changeset(page, user, edits, new_blocks \\ []) do
    entry_blocks =
      Enum.map(page.entry_blocks, fn entry_block ->
        Page.Blocks.changeset(entry_block, %{"block" => block_params(entry_block.block, edits)}, user.id, true)
      end)

    page
    |> Page.changeset(%{}, user)
    |> Ecto.Changeset.put_assoc(:entry_blocks, entry_blocks ++ new_blocks)
  end

  defp block_params(block, edits) do
    params = %{"id" => to_string(block.id)}

    params =
      if block.children == [],
        do: params,
        else: Map.put(params, "children", Enum.map(block.children, &block_params(&1, edits)))

    case Map.fetch(edits, block.uid) do
      {:ok, text} -> Map.put(params, "refs", Enum.map(block.refs, &ref_params(&1, text)))
      :error -> params
    end
  end

  defp ref_params(%{data: %{type: "text"}} = ref, text),
    do: %{"id" => to_string(ref.id), "data" => %{"type" => "text", "data" => %{"text" => text}}}

  defp ref_params(ref, _text), do: %{"id" => to_string(ref.id)}

  defp save!(changeset, user) do
    {:ok, page} = Brando.Pages.update_page(changeset, user)
    page
  end

  # An admin saves the module: a new var, and its text ref becomes a lede
  defp save_module(module, user, ref_name, var_key) do
    module = Repo.preload(module, [:vars, :refs], force: true)

    refs =
      Enum.map(module.refs, fn
        %{name: ^ref_name} = ref ->
          %{id: ref.id, name: ref.name, data: %{type: "text", data: %{text: "Default", type: "lede"}}}

        ref ->
          %{id: ref.id}
      end)

    vars = Enum.map(module.vars, &%{id: &1.id}) ++ [%{type: "string", key: var_key, label: "Added", value: "Added"}]

    {:ok, module} = Content.update_module(module, %{vars: vars, refs: refs}, user)
    module
  end

  defp saved_block(uid), do: Repo.one!(from(b in Block, where: b.uid == ^uid, preload: [:vars, :refs]))

  defp var_keys(block), do: block.vars |> Enum.map(& &1.key) |> Enum.sort()
  defp ref_data(block, name), do: Enum.find(block.refs, &(&1.name == name)).data.data

  describe "a block behind its module" do
    test "a nested block keeps the module's var and settings and the editor's edit", c do
      c = Brando.ProposalFixtures.multi_context(c)
      stamp(c.project_module)
      [alpha, beta | _] = c.child_uids
      page = loaded(c.work)

      module = save_module(c.project_module, c.user, "info", "credit")
      page |> form_changeset(c.user, %{alpha => "<p>Alpha, edited</p>"}) |> save!(c.user)

      block = saved_block(alpha)
      assert var_keys(block) == ["credit", "size"]
      assert ref_data(block, "info").text == "<p>Alpha, edited</p>"
      assert ref_data(block, "info").type == :lede
      assert block.module_version == module.version

      # The block the save did not write is as the module save left it
      assert var_keys(saved_block(beta)) == ["credit", "size"]
    end

    test "a ref setting the save changes is kept over the module's", c do
      stamp(c.text_module)
      page = loaded(c.identity)
      [%{block: %{uid: first, refs: [body]}} | _] = page.entry_blocks
      save_module(c.text_module, c.user, "body", "heading")

      entry_blocks =
        Enum.map(page.entry_blocks, fn %{block: block} = entry_block ->
          refs =
            if block.uid == first,
              do: [%{"id" => to_string(body.id), "data" => %{"type" => "text", "data" => %{"type" => "lead"}}}],
              else: []

          Page.Blocks.changeset(
            entry_block,
            %{"block" => %{"id" => to_string(block.id), "refs" => refs}},
            c.user.id,
            true
          )
        end)

      page |> Page.changeset(%{}, c.user) |> Ecto.Changeset.put_assoc(:entry_blocks, entry_blocks) |> save!(c.user)

      block = saved_block(first)
      assert var_keys(block) == ["heading"]
      assert ref_data(block, "body").type == :lead
    end
  end

  describe "a save with nothing behind" do
    test "writes what the form sent and nothing else", c do
      stamp(c.text_module)
      page = loaded(c.identity)
      [first | _] = Enum.map(page.entry_blocks, & &1.block.uid)

      changeset = form_changeset(page, c.user, %{first => "<p>Edited</p>"})
      assert Blocks.sync_written_blocks(changeset) == changeset
    end

    test "leaves the blocks it does not write alone, though they are behind", c do
      stamp(c.text_module)
      page = loaded(c.identity)
      [first | _] = Enum.map(page.entry_blocks, & &1.block.uid)
      save_module(c.text_module, c.user, "body", "heading")

      changeset = form_changeset(page, c.user, %{first => "<p>Edited</p>"})
      synced = Blocks.sync_written_blocks(changeset)

      [_first | others] = Ecto.Changeset.get_change(changeset, :entry_blocks)
      [synced_first | synced_others] = Ecto.Changeset.get_change(synced, :entry_blocks)
      assert synced_others == others
      refute synced_first == hd(Ecto.Changeset.get_change(changeset, :entry_blocks))
    end
  end
end
