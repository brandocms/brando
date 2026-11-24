defmodule Brando.Content.SaveSyncsBlocksTest do
  # An entry save writes its changes to a block onto the block as it is
  # saved, which a module save may have synced since the form loaded it
  # (#3901). Each save here is the form's: the entry's blocks as the
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

  # The form's save of `page` with `params` for the blocks it names by uid
  defp form_changeset_with(page, user, params_by_uid) do
    entry_blocks =
      Enum.map(page.entry_blocks, fn %{block: block} = entry_block ->
        params = Map.merge(%{"id" => to_string(block.id)}, Map.get(params_by_uid, block.uid, %{}))
        Page.Blocks.changeset(entry_block, %{"block" => params}, user.id, true)
      end)

    page
    |> Page.changeset(%{}, user)
    |> Ecto.Changeset.put_assoc(:entry_blocks, entry_blocks)
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

  defp add_var(module, user, key) do
    module = Repo.preload(module, [:vars, :refs], force: true)
    vars = Enum.map(module.vars, &%{id: &1.id}) ++ [%{type: "string", key: key, label: "Added", value: "Added"}]
    {:ok, module} = Content.update_module(module, %{vars: vars}, user)
    module
  end

  # A page with one Case block, as the module builds it
  defp case_page!(c, uri) do
    page = Brando.Factory.insert(:page, creator: c.user, title: uri, uri: uri)

    {:ok, block} =
      c.case_module.id |> Blocks.build_module_block(c.user.id, nil, to_string(Page.Blocks), :module) |> Repo.insert()

    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    page
  end

  defp saved_block(uid), do: Repo.one!(from(b in Block, where: b.uid == ^uid, preload: [:vars, :refs]))

  # The sources of the queries `fun` runs in this process
  defp queries(fun) do
    test = self()
    id = "save-sync-queries-#{System.unique_integer([:positive])}"
    event = Repo.config()[:telemetry_prefix] ++ [:query]

    :telemetry.attach(
      id,
      event,
      fn _event, _measurements, meta, _ -> if self() == test, do: send(test, {:query, meta.source}) end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(id)
    end

    collect_queries([])
  end

  defp collect_queries(sources) do
    receive do
      {:query, source} -> collect_queries([source | sources])
    after
      0 -> Enum.reverse(sources)
    end
  end

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

  describe "a block whose saved rows changed since the form loaded it" do
    test "a module save that changes only a ref's settings", c do
      stamp(c.text_module)
      page = loaded(c.identity)
      [first | _] = Enum.map(page.entry_blocks, & &1.block.uid)

      module = Repo.preload(c.text_module, :refs, force: true)
      [body] = module.refs
      lede = %{id: body.id, name: "body", data: %{type: "text", data: %{text: "Default body", type: "lede"}}}
      {:ok, saved_module} = Content.update_module(module, %{refs: [lede]}, c.user)
      assert saved_module.version == Repo.reload!(c.text_module).version
      assert ref_data(saved_block(first), "body").type == :lede

      page |> form_changeset(c.user, %{first => "<p>Edited</p>"}) |> save!(c.user)

      block = saved_block(first)
      assert ref_data(block, "body").type == :lede
      assert ref_data(block, "body").text == "<p>Edited</p>"
    end

    test "a ref the save did not change keeps what another save wrote", c do
      add_var(c.text_module, c.user, "heading")
      stamp(c.text_module)
      page = loaded(c.identity)
      [%{block: %{uid: first, refs: [body], vars: [heading]}} | _] = page.entry_blocks

      save_module(c.text_module, c.user, "body", "credit")
      saved_body = Repo.get!(Brando.Content.Ref, body.id)
      other = %{saved_body.data | data: %{saved_body.data.data | text: "<p>Another save</p>"}}
      saved_body |> Ecto.Changeset.change(data: other) |> Repo.update!()

      # The form sends the block as it holds it, with the var edited
      params = %{
        "refs" => [
          %{"id" => to_string(body.id), "data" => %{"type" => "text", "data" => %{"text" => body.data.data.text}}}
        ],
        "vars" => [%{"id" => to_string(heading.id), "value" => "Mine"}]
      }

      page |> form_changeset_with(c.user, %{first => params}) |> save!(c.user)

      block = saved_block(first)
      assert ref_data(block, "body").text == "<p>Another save</p>"
      assert ref_data(block, "body").type == :lede
      assert var_keys(block) == ["credit", "heading"]
      assert Enum.find(block.vars, &(&1.key == "heading")).value == "Mine"
    end

    test "another editor's save keeps the settings it wrote on refs this save did not change", c do
      page = case_page!(c, "two-editors")
      editor_a = loaded(page)
      editor_b = loaded(page)
      [%{block: %{uid: uid, refs: refs, vars: vars}}] = editor_a.entry_blocks
      cover = Enum.find(refs, &(&1.name == "cover"))
      heading = Enum.find(vars, &(&1.key == "heading"))

      alt = %{
        "refs" => [
          %{"id" => to_string(cover.id), "data" => %{"type" => "picture", "data" => %{"alt" => "A's alt"}}}
        ]
      }

      editor_a |> form_changeset_with(c.user, %{uid => alt}) |> save!(c.user)

      # B saves before the reload of A's save reaches B's block field
      vars = %{"vars" => [%{"id" => to_string(heading.id), "value" => "B's heading"}]}
      editor_b |> form_changeset_with(c.user, %{uid => vars}) |> save!(c.user)

      block = saved_block(uid)
      assert ref_data(block, "cover").alt == "A's alt"
      assert Enum.find(block.vars, &(&1.key == "heading")).value == "B's heading"
    end

    test "a var the form fetched that a module save added is saved once, with the editor's value", c do
      stamp(c.text_module)
      page = loaded(c.identity)
      [%{block: %{uid: first, refs: [body]}} | _] = page.entry_blocks

      save_module(c.text_module, c.user, "body", "headline")

      # "Fetch missing vars": the module's var, without a primary key
      params = %{
        "refs" => [%{"id" => to_string(body.id)}],
        "vars" => [%{"type" => "string", "key" => "headline", "label" => "Added", "value" => "The editor's"}]
      }

      page |> form_changeset_with(c.user, %{first => params}) |> save!(c.user)

      block = saved_block(first)
      assert var_keys(block) == ["headline"]
      assert hd(block.vars).value == "The editor's"
    end
  end

  describe "the page a save stores" do
    # The form renders its own copy of the blocks before it saves
    # (`Blocks.render_block_fields/1`); a save that rebuilt a stale block
    # from its saved rows renders the entry again once it has committed
    defp rendered_save(changeset, user) do
      Oban.Testing.with_testing_mode(:manual, fn ->
        changeset |> Blocks.render_block_fields() |> save!(user)
        all_enqueued(worker: Brando.Worker.EntryRenderer, args: %{entry_id: changeset.data.id})
      end)
    end

    defp rendered(page), do: Repo.get!(Page, page.id).rendered_blocks

    test "after a module save shows the module's settings and var with the editor's edit", c do
      stamp(c.text_module)
      page = loaded(c.identity)
      [first | _] = Enum.map(page.entry_blocks, & &1.block.uid)
      save_module(c.text_module, c.user, "body", "heading")

      [job] = page |> form_changeset(c.user, %{first => "<p>Edited</p>"}) |> rendered_save(c.user)
      refute rendered(page) =~ ~s(<div class="lede"><p>Edited</p></div>)

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      assert rendered(page) =~ ~s(<p>Added</p><div class="lede"><p>Edited</p></div>)
    end

    test "shows the text another save wrote to a ref this save did not change", c do
      add_var(c.text_module, c.user, "heading")
      stamp(c.text_module)
      page = loaded(c.identity)
      [%{block: %{uid: first, refs: [body], vars: [heading]}} | _] = page.entry_blocks

      saved_body = Repo.get!(Brando.Content.Ref, body.id)
      other = %{saved_body.data | data: %{saved_body.data.data | text: "<p>Another save</p>"}}
      saved_body |> Ecto.Changeset.change(data: other) |> Repo.update!()

      params = %{
        "refs" => [%{"id" => to_string(body.id)}],
        "vars" => [%{"id" => to_string(heading.id), "value" => "Mine"}]
      }

      [job] = page |> form_changeset_with(c.user, %{first => params}) |> rendered_save(c.user)
      refute rendered(page) =~ "<p>Another save</p>"

      assert {:ok, _} = perform_job(Brando.Worker.EntryRenderer, job.args)
      assert rendered(page) =~ ~s(<p>Mine</p><div class="paragraph"><p>Another save</p></div>)
    end

    test "a save with nothing stale queues no render of the entry", c do
      stamp(c.text_module)
      page = loaded(c.identity)
      [first | _] = Enum.map(page.entry_blocks, & &1.block.uid)

      assert [] = page |> form_changeset(c.user, %{first => "<p>Edited</p>"}) |> rendered_save(c.user)
      assert rendered(page) =~ "<p>Edited</p>"
    end
  end

  describe "a block the form holds as it is saved" do
    # A Case block from before version tracking, with a ref its module no
    # longer defines: `sync_module/2` never stamps it
    setup c do
      page = Brando.Factory.insert(:page, creator: c.user, title: "Case", uri: "case")

      refs = [
        %{"uid" => Brando.Utils.generate_uid(), "name" => "cover", "data" => %{"type" => "picture", "data" => %{}}},
        %{
          "uid" => Brando.Utils.generate_uid(),
          "name" => "legacy",
          "data" => %{"type" => "text", "data" => %{"text" => "<p>Old</p>"}}
        }
      ]

      block =
        %Block{}
        |> Block.recursive_block_changeset(
          %{
            "uid" => "unstampable",
            "type" => "module",
            "module_id" => c.case_module.id,
            "creator_id" => c.user.id,
            "source" => to_string(Page.Blocks),
            "refs" => Enum.with_index(refs, &Map.put(&1, "sequence", &2))
          },
          c.user
        )
        |> Repo.insert!()

      Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
      %{case_page: page}
    end

    test "keeps the editor's settings over two saves, and nothing is synced", c do
      page = loaded(c.case_page)
      [cover, legacy] = hd(page.entry_blocks).block.refs

      alt = %{
        "refs" => [
          %{"id" => to_string(cover.id), "data" => %{"type" => "picture", "data" => %{"alt" => "The editor's alt"}}},
          %{"id" => to_string(legacy.id)}
        ]
      }

      page |> form_changeset_with(c.user, %{"unstampable" => alt}) |> save!(c.user)
      assert ref_data(saved_block("unstampable"), "cover").alt == "The editor's alt"

      text = %{
        "refs" => [
          %{"id" => to_string(cover.id)},
          %{"id" => to_string(legacy.id), "data" => %{"type" => "text", "data" => %{"text" => "<p>New</p>"}}}
        ]
      }

      changeset = c.case_page |> loaded() |> form_changeset_with(c.user, %{"unstampable" => text})
      synced = Blocks.sync_written_blocks(changeset)
      save!(changeset, c.user)

      block = saved_block("unstampable")
      assert ref_data(block, "cover").alt == "The editor's alt"
      assert synced == changeset
      assert ref_data(block, "legacy").text == "<p>New</p>"
      assert Enum.map(block.refs, & &1.name) == ["cover", "legacy"]
      assert block.vars == []
      assert block.module_version == nil
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

    test "runs no query when the save writes no blocks", c do
      changeset = Page.changeset(loaded(c.identity), %{"title" => "Renamed"}, c.user)
      assert queries(fn -> Blocks.sync_written_blocks(changeset) end) == []
    end

    test "loads no module when no written block is stale", c do
      stamp(c.text_module)
      page = loaded(c.identity)
      edits = Map.new(page.entry_blocks, &{&1.block.uid, "<p>Edited</p>"})
      changeset = form_changeset(page, c.user, edits)

      sources = queries(fn -> Blocks.sync_written_blocks(changeset) end)
      refute "content_modules" in sources
      assert length(sources) <= 3
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
