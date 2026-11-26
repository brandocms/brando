defmodule Brando.Content.DefinitionDropsTest do
  # brandocms/brando#3996, unit B: a release apply asked to drops what blocks
  # hold in the refs and vars it removes, keeps each row for Revert, and
  # Revert puts them back.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Block, Blocks, DefinitionDrop, Definitions, Module, Ref, StaleBlocks, Var}
  alias Brando.Content.Definition.Drops
  alias Brando.Content.Definitions.Release
  alias Brando.Content.Definitions.Release.Batches
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Repo

  setup do
    user = Brando.Factory.insert(:random_user)

    module =
      ProposalFixtures.module!(user, "Teaser", "<p>{{ tagline }}</p>{% ref refs.body %}",
        refs: [ProposalFixtures.ref("body", %{type: "text", data: %{text: "Default body"}})],
        vars: [%{type: "string", key: "tagline", label: "Tagline", value: "Default tagline"}]
      )

    identity = ProposalFixtures.page!(user, "Identity", module)
    naming = ProposalFixtures.page!(user, "Naming", module)

    path = Path.join(System.tmp_dir!(), "brando-drops-#{System.unique_integer([:positive])}")
    {:ok, _} = Definitions.export(path, user, uids: [module.uid])
    on_exit(fn -> File.rm_rf!(path) end)

    c = %{user: user, module: module, identity: identity, naming: naming, path: path}
    adopt!(c)
    c
  end

  # The files exported again, for `uids`, and recorded as applied
  defp export!(c, uids) do
    File.rm_rf!(c.path)
    {:ok, _} = Definitions.export(c.path, c.user, uids: uids)
    adopt!(c)
  end

  defp adopt!(c) do
    File.rm(Path.join(c.path, "modules.lock.json"))
    assert {:ok, %{adopted: adopted}} = Release.plan(path: c.path, version: "1.0.0")
    assert adopted > 0
  end

  defp opts(c), do: [path: c.path, version: "2.0.0", user: c.user.id]
  defp exs(c, name), do: Path.join(c.path, "content/#{name}.exs")

  defp blocks(page) do
    Repo.all(
      from(b in Block,
        join: j in Page.Blocks,
        on: j.block_id == b.id,
        where: j.entry_id == ^page.id,
        order_by: j.sequence
      )
    )
  end

  defp first_block(page), do: page |> blocks() |> hd()

  # A `tagline` var holding `value` in `block`
  defp hold!(block, value, attrs \\ []) do
    Repo.insert!(
      struct(%Var{block_id: block.id, key: "tagline", type: :string, label: %{"en" => "Tagline"}, value: value}, attrs)
    )

    block
  end

  defp hold_body!(block, text) do
    Repo.insert!(%Ref{
      block_id: block.id,
      name: "body",
      uid: Brando.Utils.generate_uid(),
      data: %Brando.Villain.Blocks.TextBlock{type: "text", data: %Brando.Villain.Blocks.TextBlock.Data{text: text}}
    })

    block
  end

  defp vars(block, key), do: Repo.all(from(v in Var, where: v.block_id == ^block.id and v.key == ^key, order_by: v.id))
  defp var(block, key), do: List.first(vars(block, key))
  defp ref(block, name), do: Repo.get_by(Ref, block_id: block.id, name: name)
  defp module(c), do: Repo.get!(Module, c.module.id)

  defp edit!(c, from, to, name \\ "teaser") do
    source = File.read!(exs(c, name))
    edited = Regex.replace(from, source, to)
    assert edited != source
    File.write!(exs(c, name), edited)
  end

  defp remove_tagline!(c), do: edit!(c, ~r/\n    var "tagline", "string" do\n.*?\n    end\n/s, "\n")
  defp remove_body!(c), do: edit!(c, ~r/\n    ref "body", "text" do\n.*?\n    end\n/s, "\n")

  defp drops(c, selection \\ :all) do
    {:ok, drops} = Release.drops(selection, opts(c))
    drops
  end

  defp apply!(c, drops) do
    assert {:ok, %{batch_id: batch_id} = applied} =
             Release.apply(:all, opts(c) ++ [wait: false, drop: drops.digest])

    Map.put(applied, :batch, Batches.get(batch_id))
  end

  defp revert!(c, batch) do
    assert {:ok, result} = Batches.revert(Batches.get(batch.batch_id), c.user)
    result
  end

  defp stored(batch), do: Repo.all(from(d in DefinitionDrop, where: d.batch_id == ^batch.batch_id, order_by: d.id))

  defp capture_queries(fun) do
    handler = "drops-queries-#{System.unique_integer([:positive])}"
    test = self()
    event = Brando.repo().config()[:telemetry_prefix] ++ [:query]
    :telemetry.attach(handler, event, fn _event, _measures, meta, _ -> send(test, {:query, meta.query}) end, nil)

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries([])
  end

  defp collect_queries(acc) do
    receive do
      {:query, query} -> collect_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp revisions(page),
    do: Repo.all(from(r in Brando.Revisions.Revision, where: r.entry_id == ^page.id, order_by: r.revision))

  describe "an apply that drops" do
    test "deletes the values of a removed var, keeps each row whole, and Revert puts them back", c do
      holder = c.identity |> first_block() |> hold!("Kept words")
      remove_tagline!(c)

      drops = drops(c)
      assert [%{uid: uid, keys: [var: "tagline"], blocks: 1}] = drops.modules
      assert uid == c.module.uid
      assert drops.left == [] and drops.over_limit == nil
      before = length(revisions(c.identity))

      %{batch: batch, result: result} = apply!(c, drops)
      assert result.dropped == %{c.module.uid => %{blocks: 1, values: 1}}
      assert var(holder, "tagline") == nil
      assert StaleBlocks.count_with_leftovers(module(c)) == 0
      assert Blocks.list_stale_block_ids(module(c)) == []
      assert Drops.blocks(batch.batch_id) == 1

      assert [%DefinitionDrop{block_id: block_id, kind: "var", key: "tagline", row: row}] = stored(batch)
      assert block_id == holder.id
      assert row["value"] == "Kept words" and row["type"] == "string" and is_integer(row["id"])

      # A revision before and one after; the entries' Activity says what went
      assert length(revisions(c.identity)) == before + 2

      assert Repo.aggregate(
               from(e in Brando.Activity.Event,
                 where: e.schema == ^to_string(Page) and e.entry_id == ^c.identity.id,
                 where: fragment("? \\? 'dropped'", e.details)
               ),
               :count
             ) == 1

      result = revert!(c, batch)
      assert %{"values" => 1, "blocks" => 1, "skipped" => %{}, "left" => 0} = result.dropped
      assert var(holder, "tagline").value == "Kept words"
      assert stored(batch) == []
      assert StaleBlocks.count(module(c)) == 0
      assert length(revisions(c.identity)) == before + 4
    end

    test "with nothing held drops nothing, records nothing and applies", c do
      remove_tagline!(c)
      drops = drops(c)
      assert drops.modules == []

      %{batch: batch, result: result} = apply!(c, drops)
      assert result.dropped == %{}
      assert stored(batch) == []
      assert Repo.preload(module(c), :vars).vars == []
    end

    test "uses the values as they are under the lock, when an editor saved since the review", c do
      holder = c.identity |> first_block() |> hold!("Before")
      remove_tagline!(c)
      drops = drops(c)

      Repo.update_all(from(v in Var, where: v.block_id == ^holder.id), set: [value: "Saved since"])
      %{batch: batch} = apply!(c, drops)
      assert [%{row: %{"value" => "Saved since"}}] = stored(batch)
    end

    test "is refused, applying nothing, when the removals blocks hold changed since the review", c do
      Repo.delete_all(from(r in Ref, where: not is_nil(r.block_id)))
      c.identity |> first_block() |> hold!("Words")
      remove_tagline!(c)
      remove_body!(c)
      drops = drops(c)
      assert [%{keys: [var: "tagline"]}] = drops.modules

      # The body ref is held now, which the review didn't show
      c.naming |> first_block() |> hold_body!("New body")

      assert {:error, reason} = Release.apply(:all, opts(c) ++ [wait: false, drop: drops.digest])
      assert reason =~ "changed since you reviewed it"
      assert [%{key: "tagline"}] = Repo.preload(module(c), :vars).vars
      assert Repo.aggregate(DefinitionDrop, :count) == 0
    end

    test "without drop: leaves the values as leftovers, as every other caller does", c do
      holder = c.identity |> first_block() |> hold!("Kept words")
      remove_tagline!(c)

      assert {:ok, %{result: %{dropped: dropped}}} = Release.apply(:all, opts(c) ++ [wait: false])
      assert dropped == %{}
      assert var(holder, "tagline").value == "Kept words"
      assert StaleBlocks.count_with_leftovers(module(c)) == 1
      assert Repo.aggregate(DefinitionDrop, :count) == 0
    end

    test "leaves a declared rename's source whose destination existed, and drops an unrelated removal", c do
      # The module defines both; the release removes `tagline` and declares
      # `heading` renamed from it, and removes `body`
      c.module
      |> Repo.preload(:vars)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:vars, [
        %{type: :string, key: "tagline", label: %{"en" => "Tagline"}, creator_id: c.user.id},
        %{type: :string, key: "heading", label: %{"en" => "Heading"}, creator_id: c.user.id}
      ])
      |> Repo.update!()

      export!(c, [c.module.uid])
      holder = c.identity |> first_block() |> hold!("Old words")
      remove_tagline!(c)
      remove_body!(c)
      edit!(c, ~r/var "heading", "string" do\n/, ~s(var "heading", "string" do\n      renamed_from "tagline"\n))

      drops = drops(c)
      assert [%{keys: [ref: "body"]}] = drops.modules

      apply!(c, drops)
      assert var(holder, "tagline").value == "Old words"
      assert ref(holder, "body") == nil
    end

    test "leaves the blocks of a shared-library module with the same id", c do
      holder = c.identity |> first_block() |> hold!("Shared words")
      Repo.update_all(from(b in Block, where: b.id == ^holder.id), set: [module_origin: :shared])
      remove_tagline!(c)

      assert drops(c).modules == []
    end

    test "leaves a ref whose slot holds blocks or footnotes, and counts those blocks", c do
      # Every block holds the body ref
      [slotted, noted, plain] = blocks(c.identity)

      region =
        Repo.insert!(%Block{
          uid: Brando.Utils.generate_uid(),
          type: :slot,
          slot_kind: :region,
          slot_name: "body",
          parent_id: slotted.id
        })

      Repo.insert!(%Block{uid: Brando.Utils.generate_uid(), type: :module, module_id: c.module.id, parent_id: region.id})

      Repo.insert!(%Block{
        uid: Brando.Utils.generate_uid(),
        type: :slot,
        slot_kind: :footnote,
        slot_name: "body",
        parent_id: noted.id
      })

      remove_body!(c)

      drops = drops(c)
      assert [%{keys: [ref: "body"], blocks: 4, rows: rows}] = drops.modules
      assert plain.id in Enum.map(rows, & &1.block_id)
      refute Enum.any?(rows, &(&1.block_id in [slotted.id, noted.id]))
      assert drops.slotted == 2

      apply!(c, drops)
      assert ref(plain, "body") == nil
      assert ref(slotted, "body") && ref(noted, "body")
    end
  end

  describe "a module whose apply Revert couldn't undo" do
    test "keeps a leftover of another type: the reverse needs a migration, so nothing of it is dropped", c do
      c.identity |> first_block() |> hold!("Words")
      c.naming |> first_block() |> hold!("Long words", type: :text)
      remove_tagline!(c)

      drops = drops(c)
      assert drops.modules == []
      assert [%{uid: uid, blocker: uid, reason: reason}] = drops.left
      assert uid == c.module.uid
      assert reason =~ "returns as string"
    end

    test "or one that moves renamed values is left, beside another module that drops", c do
      other =
        ProposalFixtures.module!(c.user, "Other", "<p>{{ fresh }}</p>",
          vars: [
            %{type: "string", key: "stale", label: "Stale", value: ""},
            %{type: "string", key: "gone", label: "Gone", value: ""}
          ]
        )

      page = ProposalFixtures.page!(c.user, "Other page", other)
      export!(c, [c.module.uid, other.uid])

      other_block = first_block(page)

      for key <- ~w(stale gone),
          do: Repo.insert!(%Var{block_id: other_block.id, key: key, type: :string, label: %{"en" => key}, value: key})

      holder = c.identity |> first_block() |> hold!("Kept words")
      remove_tagline!(c)
      edit!(c, ~r/var "stale", "string" do\n/, ~s(var "fresh", "string" do\n      renamed_from "stale"\n), "other")
      edit!(c, ~r/\n    var "gone", "string" do\n.*?\n    end\n/s, "\n", "other")

      drops = drops(c)
      assert [%{uid: teaser}] = drops.modules
      assert teaser == c.module.uid
      assert [%{uid: other_uid, reason: reason}] = drops.left
      assert other_uid == other.uid
      assert reason =~ "stale → fresh"

      %{batch: batch} = apply!(c, drops)
      assert var(holder, "tagline") == nil
      assert var(other_block, "fresh").value == "stale"
      assert var(other_block, "gone").value == "gone"

      result = revert!(c, batch)
      assert %{"values" => 1} = result.dropped
      assert var(holder, "tagline").value == "Kept words"
    end
  end

  describe "a tree" do
    # A Row whose Cell blocks hold `caption`
    setup c do
      row = ProposalFixtures.module!(c.user, "Row", "<div>{{ content }}</div>", multi: true)

      cell =
        ProposalFixtures.module!(c.user, "Cell", "<p>{{ caption }}</p>",
          parent_id: row.id,
          vars: [%{type: "string", key: "caption", label: "Caption", value: "Default caption"}]
        )

      export!(c, [row.uid])
      page = Brando.Factory.insert(:page, creator: c.user, title: "Grid", uri: "grid")

      parent =
        Repo.insert!(%Block{
          uid: Brando.Utils.generate_uid(),
          type: :module,
          multi: true,
          module_id: row.id,
          source: Page.Blocks
        })

      Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: parent.id, sequence: 0})

      held =
        Repo.insert!(%Block{
          uid: Brando.Utils.generate_uid(),
          type: :module_entry,
          module_id: cell.id,
          parent_id: parent.id,
          source: Page.Blocks
        })

      Repo.insert!(%Var{block_id: held.id, key: "caption", type: :string, label: %{"en" => "Caption"}, value: "Cell words"})
      %{row: row, cell: cell, held: held}
    end

    test "whose root the apply adds a child to keeps the leftovers of its other modules, as Revert can't undo it", c do
      # A new child of Row, and Cell without its caption
      content = Path.join(c.path, "content/row")
      extra = "extra-#{System.unique_integer([:positive])}"

      File.write!(
        Path.join(content, "extra.exs"),
        content
        |> Path.join("cell.exs")
        |> File.read!()
        |> String.replace(~s(uid "#{c.cell.uid}"), ~s(uid "#{extra}"))
        |> String.replace("Row.Cell do", "Row.Extra do")
        |> String.replace("cell.liquid", "extra.liquid")
      )

      File.write!(Path.join(content, "extra.liquid"), "<p>Extra</p>")
      edit!(c, ~r/    child "#{c.cell.uid}"\n/, ~s(    child "#{c.cell.uid}"\n    child "#{extra}"\n), "row")
      edit!(c, ~r/\n  vars do\n.*?\n  end\n/s, "\n", "row/cell")

      drops = drops(c)
      assert drops.modules == []
      assert [%{uid: cell, blocker: row, reason: "removing child definitions requires a migration"}] = drops.left
      assert {cell, row} == {c.cell.uid, c.row.uid}

      # As Revert finds it after the apply
      %{batch: batch} = apply!(c, drops)
      assert var(c.held, "caption").value == "Cell words"
      assert {:ok, %{irreversible: irreversible}} = Batches.preview(batch, c.user)
      assert c.row.uid in Enum.map(irreversible, & &1.uid)
    end

    test "drops a child's values when nothing in it blocks Revert", c do
      edit!(c, ~r/\n  vars do\n.*?\n  end\n/s, "\n", "row/cell")

      drops = drops(c)
      assert [%{uid: cell, keys: [var: "caption"]}] = drops.modules
      assert cell == c.cell.uid

      %{batch: batch} = apply!(c, drops)
      assert var(c.held, "caption") == nil
      assert %{"values" => 1} = revert!(c, batch).dropped
      assert var(c.held, "caption").value == "Cell words"
    end
  end

  describe "over the limit" do
    test "drops nothing: the plan says so, and an apply asked to is refused", c do
      now = NaiveDateTime.utc_now(:second)

      blocks =
        for _ <- 1..1501 do
          %{uid: Brando.Utils.generate_uid(), type: :module, module_id: c.module.id, inserted_at: now, updated_at: now}
        end

      {_, ids} = Repo.insert_all(Block, blocks, returning: [:id])

      Repo.insert_all(
        Var,
        for %{id: id} <- ids do
          %{block_id: id, key: "tagline", type: :string, label: %{"en" => "Tagline"}, value: "Words", inserted_at: now, updated_at: now}
        end
      )

      remove_tagline!(c)

      drops = drops(c)
      assert [%{blocks: 1501}] = drops.modules
      assert %{blocks: 1501} = drops.over_limit
      assert drops.entries == []

      assert {:error, reason} = Release.apply(:all, opts(c) ++ [wait: false, drop: drops.digest])
      assert reason =~ "1500 blocks"
      assert Repo.aggregate(DefinitionDrop, :count) == 0
    end
  end

  describe "a scheduled version" do
    test "that publishes between the apply and Revert brings its values back as leftovers, and Revert skips them", c do
      holder = c.identity |> first_block() |> hold!("Scheduled words")
      {:ok, %{revision: revision}} = Brando.Revisions.create_revision(Repo.get!(Page, c.identity.id), c.user, false)
      {1, _} = Brando.Revisions.mark_revision_scheduled(Page, c.identity.id, revision, true)
      remove_tagline!(c)

      %{batch: batch} = apply!(c, drops(c))
      assert var(holder, "tagline") == nil

      job = %Oban.Job{
        attempt: 1,
        max_attempts: 10,
        args: %{"schema" => to_string(Page), "id" => c.identity.id, "revision" => revision, "user_id" => c.user.id}
      }

      assert {:ok, _} = Brando.Worker.EntryPublisher.perform(job)
      [restored] = c.identity |> blocks() |> Enum.filter(&var(&1, "tagline"))
      assert var(restored, "tagline").value == "Scheduled words"
      assert StaleBlocks.count_with_leftovers(module(c)) == 1

      assert %{"values" => 0, "skipped" => %{"filled" => 1}} = revert!(c, batch).dropped
      assert Enum.map(vars(restored, "tagline"), & &1.value) == ["Scheduled words"]
    end
  end

  describe "planning and status" do
    test "do not load the dropped rows", c do
      c.identity |> first_block() |> hold!("Kept words")
      remove_tagline!(c)
      %{batch: batch} = apply!(c, drops(c))
      [row] = stored(batch)
      Repo.insert_all(DefinitionDrop, for(_ <- 1..2000, do: row |> Map.from_struct() |> Map.drop([:__meta__, :id])))

      queries = capture_queries(fn ->
        {:ok, _} = Release.plan(opts(c))
        Batches.status(Batches.pending(), c.user)
        assert Drops.blocks(batch.batch_id) == 1
      end)

      assert [count] = Enum.filter(queries, &(&1 =~ "content_definition_drops"))
      assert count =~ "count(DISTINCT"
    end
  end

  describe "authorization" do
    test "is the right to apply: the drop goes through entries the operator may not edit", c do
      put_test_env(:authorization_mode, :groups)
      assert {:ok, _} = Brando.Authorization.Migration.run()
      scope = Brando.Authorization.Scope.standalone(c.user)
      applier = Brando.Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})

      {:ok, group} =
        Brando.Authorization.Groups.create(scope, %{name: "Appliers"}, [
          "brando.admin.access",
          "brando.module_definitions.apply"
        ])

      {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, applier.id)
      assert Brando.Authorization.Boundary.authorize_record(applier, :update, Page, c.identity.id) != :ok

      holder = c.identity |> first_block() |> hold!("Kept words")
      remove_tagline!(c)
      opts = [path: c.path, version: "2.0.0", user: applier.id]
      {:ok, drops} = Release.drops(:all, opts)

      assert {:ok, %{result: %{dropped: dropped}, batch_id: batch_id}} =
               Release.apply(:all, opts ++ [wait: false, drop: drops.digest])

      assert map_size(dropped) == 1
      assert var(holder, "tagline") == nil
      assert {:ok, %{dropped: %{"values" => 1}}} = Batches.revert(Batches.get(batch_id), applier)
      assert var(holder, "tagline").value == "Kept words"
    end
  end

  describe "Revert after a drop" do
    setup c do
      [first, second, third] = blocks(c.identity)
      [gone, moved, filled] = blocks(c.naming)
      for block <- [first, second, third, gone, moved, filled], do: hold!(block, "Value #{block.id}")
      # Two rows for one key
      hold!(first, "Second value")
      remove_tagline!(c)
      %{batch: batch} = apply!(c, drops(c))
      assert length(stored(batch)) == 7
      %{batch: batch, kept: [first, second, third], gone: gone, moved: moved, filled: filled}
    end

    test "puts back each value it can, and counts those it can't by reason", c do
      Repo.delete_all(from(b in Block, where: b.id == ^c.gone.id))
      other = ProposalFixtures.module!(c.user, "Elsewhere", "<p></p>", [])
      Repo.update_all(from(b in Block, where: b.id == ^c.moved.id), set: [module_id: other.id])
      hold!(c.filled, "Filled since")

      result = revert!(c, c.batch)

      assert result.dropped == %{
               "values" => 4,
               "blocks" => 3,
               "skipped" => %{"block_gone" => 1, "other_module" => 1, "filled" => 1},
               "left" => 0
             }

      [first, second, third] = c.kept
      assert Enum.map(vars(first, "tagline"), & &1.value) == ["Value #{first.id}", "Second value"]
      assert var(second, "tagline").value == "Value #{second.id}"
      assert var(third, "tagline").value == "Value #{third.id}"
      assert Enum.map(vars(c.filled, "tagline"), & &1.value) == ["Filled since"]
      assert var(c.moved, "tagline") == nil
      # What went back is not kept twice; what didn't stays with the record
      assert length(stored(c.batch)) == 3
    end

    test "puts the values back in the blocks of an entry in the trash", c do
      {:ok, _} = Brando.Pages.delete_page(c.identity.id, c.user)
      result = revert!(c, c.batch)
      assert result.dropped["values"] == 7
      assert var(hd(c.kept), "tagline")
    end

    test "leaves the values of a module changed here since, with the record", c do
      module(c) |> Ecto.Changeset.change(help_text: %{"en" => "Edited here"}) |> Repo.update!()

      result = revert!(c, c.batch)
      assert result.reverted == []
      assert %{"values" => 0, "left" => 6} = result.dropped
      assert var(hd(c.kept), "tagline") == nil
      assert length(stored(c.batch)) == 7
    end
  end

  describe "a restored row" do
    test "points at nothing that is gone, and takes a new uid when its own is taken", c do
      {:ok, form} =
        Brando.Forms.create_form(
          %{"title" => "Contact", "key" => "contact", "language" => "en", "status" => "published"},
          c.user
        )

      identifier =
        Repo.insert!(%Brando.Content.Identifier{
          schema: Page,
          entry_id: c.naming.id,
          title: "Naming",
          language: :en,
          status: :published
        })

      palette = Brando.Factory.insert(:palette)
      [linked, plain | _] = blocks(c.identity)
      hold!(linked, "Linked", form_id: form.id, identifier_id: identifier.id, palette_id: palette.id)
      hold!(plain, "Plain")
      %{uid: uid, data: %{data: %{text: text}}} = ref(linked, "body")
      remove_tagline!(c)
      remove_body!(c)

      %{batch: batch} = apply!(c, drops(c))
      Repo.delete!(form)
      Repo.delete!(identifier)
      Repo.delete!(palette)
      # Another block's ref took the uid since
      Repo.insert!(%Ref{block_id: hd(blocks(c.naming)).id, name: "other", uid: uid, data: nil})

      result = revert!(c, batch)
      # Two taglines and six bodies
      assert result.dropped["values"] == 8

      restored = var(linked, "tagline")
      assert restored.value == "Linked"
      assert is_nil(restored.form_id) and is_nil(restored.identifier_id) and is_nil(restored.palette_id)
      assert var(plain, "tagline").value == "Plain"

      body = ref(linked, "body")
      assert body.data.data.text == text
      assert body.uid != uid
    end
  end

  describe "the record" do
    setup c do
      c.identity |> first_block() |> hold!("Kept words")
      remove_tagline!(c)
      %{batch: batch} = apply!(c, drops(c))
      %{batch: batch}
    end

    test "goes with Keep, and Revert is refused after it", c do
      assert {:ok, _} = Batches.keep(c.batch, c.user)
      assert stored(c.batch) == []
      assert {:error, :kept} = Batches.revert(Batches.get(c.batch.batch_id), c.user)
    end

    test "stays when Keep finds the apply reverted", c do
      revert!(c, c.batch)
      assert {:error, :reverted} = Batches.keep(c.batch, c.user)
      assert var(c.identity |> first_block(), "tagline").value == "Kept words"
    end

    test "goes with the next apply that confirms it, and stays when that apply rolls back", c do
      {:error, :undone} =
        Repo.transaction(fn ->
          Batches.insert!(%{batch_id: Ecto.UUID.generate(), source: :release, release: "3.0.0"}, c.user.id)
          Repo.rollback(:undone)
        end)

      assert [_] = stored(c.batch)

      Batches.insert!(%{batch_id: Ecto.UUID.generate(), source: :release, release: "3.0.0"}, c.user.id)
      assert stored(c.batch) == []
    end
  end
end
