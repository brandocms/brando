defmodule Brando.Content.DefinitionRenamesTest do
  # brandocms/brando#3844: `renamed_from:` on a definition's ref or var moves
  # each block's value from the old key to the new one in the apply that
  # removes the old key and adds the new one.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Block, BlockMoves, Blocks, Definitions, Module, Ref, Var}
  alias Brando.Content.Definition.Renames
  alias Brando.Content.Definitions.Release
  alias Brando.Content.Definitions.Release.{Batches, Proposed, Verify}
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
    # Every block holds the module's refs and vars, as the editor saves them
    module.id |> Blocks.list_block_ids_using_module() |> Blocks.sync_blocks(module.id)

    path = Path.join(System.tmp_dir!(), "brando-renames-#{System.unique_integer([:positive])}")
    {:ok, _} = Definitions.export(path, user, uids: [module.uid])
    on_exit(fn -> File.rm_rf!(path) end)

    %{
      user: user,
      module: module,
      identity: identity,
      naming: naming,
      path: path,
      exs: Path.join(path, "content/teaser.exs")
    }
  end

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
  defp var(block, key), do: Repo.get_by(Var, block_id: block.id, key: key)
  defp ref(block, name), do: Repo.get_by(Ref, block_id: block.id, name: name)
  defp module(c), do: Repo.get!(Module, c.module.id)

  defp set!(block, key, value) do
    {1, _} = Repo.update_all(from(v in Var, where: v.block_id == ^block.id and v.key == ^key), set: [value: value])
    block
  end

  defp revisions(page),
    do: Repo.all(from(r in Brando.Revisions.Revision, where: r.entry_id == ^page.id, order_by: r.revision))

  defp edit!(c, from, to) do
    source = File.read!(c.exs)
    edited = String.replace(source, from, to)
    assert edited != source
    File.write!(c.exs, edited)
  end

  defp edit_template!(c, from, to) do
    file = Path.join(c.path, "content/teaser.liquid")
    File.write!(file, String.replace(File.read!(file), from, to))
  end

  # The file renames var `tagline` to `heading`, of `type`
  defp rename_tagline!(c, type \\ "string") do
    edit!(c, ~s(var "tagline", "string" do\n), ~s(var "heading", "#{type}" do\n      renamed_from "tagline"\n))
    edit_template!(c, "{{ tagline }}", "{{ heading }}")
  end

  defp rename_body!(c) do
    edit!(c, ~s(ref "body", "text" do\n), ~s(ref "copy", "text" do\n      renamed_from "body"\n))
    edit_template!(c, "{% ref refs.body %}", "{% ref refs.copy %}")
  end

  defp run_task(args) do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    Mix.Task.reenable("brando.modules")

    try do
      Mix.Tasks.Brando.Modules.run(args)
      shell_output()
    after
      Mix.shell(previous)
    end
  end

  defp shell_output(acc \\ []) do
    receive do
      {:mix_shell, _level, [message]} -> shell_output([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp import!(c, extra \\ []), do: run_task(["import", "--from", c.path, "--user", to_string(c.user.id)] ++ extra)

  defp plan!(c) do
    {:ok, bundle} = Definitions.read(c.path)
    {:ok, plan} = Definitions.plan(bundle, c.user)
    plan
  end

  describe "a rename in an import" do
    test "moves every block's value in the apply, with revisions and Activity as the person", c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      rename_tagline!(c)

      assert [%{action: :update, removes: nil, moves: moves}] = plan!(c).items
      assert [%{kind: :var, from: "tagline", to: "heading", blocks: 6, entries: 2}] = moves.renames
      assert moves.refused == []

      output = import!(c)
      assert "update module #{c.module.uid}: moves var tagline → heading in 6 blocks (2 entries)" in output
      refute Enum.any?(output, &(&1 =~ "resolve:"))

      assert var(held, "heading").value == "Kept words"
      assert var(held, "tagline") == nil
      assert var(first_block(c.naming), "heading").value == "Default tagline"
      assert Blocks.list_stale_block_ids(module(c)) == []

      # One restore point before, one after, by the person who applied
      assert [before, after_move] = revisions(c.identity)
      assert before.description == "Before applying module definitions: var tagline → heading in Teaser"
      assert before.creator_id == c.user.id
      assert after_move.active

      event =
        Repo.one(
          from(e in Brando.Activity.Event,
            where: e.schema == ^to_string(Page) and e.entry_id == ^c.identity.id,
            order_by: [desc: e.id],
            limit: 1
          )
        )

      assert event.user_id == c.user.id
      assert %{"renamed" => %{"modules" => [%{"uid" => uid, "renames" => ["var:tagline→heading"]}]}} = event.details
      assert uid == c.module.uid

      Blocks.render_entry(Page, c.identity.id)
      assert Repo.get!(Page, c.identity.id).rendered_blocks =~ "<p>Kept words</p>"

      # The declaration does nothing once applied
      assert Enum.any?(import!(c), &(&1 =~ "noop module #{c.module.uid}"))
      assert length(revisions(c.identity)) == 2
    end

    test "of a ref moves its footnotes with it; apply and Verify's in-memory rename agree", c do
      block = first_block(c.identity)
      notes = footnote!(c, block, "body")
      rename_body!(c)

      plan = plan!(c)
      assert [%{moves: %{renames: [%{kind: :ref, from: "body", to: "copy"}]}}] = plan.items
      proposed = Proposed.sync_block(load_tree(block), Proposed.build(%{plan: plan, items: plan.items}))
      assert Enum.map(proposed.refs, & &1.name) == ["copy"]
      assert [%{slot_name: "copy"}] = Enum.filter(proposed.children, &(&1.type == :slot))

      import!(c)
      assert ref(block, "copy").data.data.text == "<p>Identity 0</p>"
      assert ref(block, "body") == nil
      assert Repo.get!(Block, notes.id).slot_name == "copy"
      assert Blocks.list_stale_block_ids(module(c)) == []
    end

    test "takes the place of the block's own copy of the new key when it is empty or the default", c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      leftover!(held, "heading", "")
      other = c.naming |> first_block()
      leftover!(other, "heading", "Default tagline")
      rename_tagline!(c)

      assert [%{action: :update}] = plan!(c).items
      import!(c)
      assert [%Var{value: "Kept words"}] = Repo.all(from(v in Var, where: v.block_id == ^held.id and v.key == "heading"))

      assert [%Var{value: "Default tagline"}] =
               Repo.all(from(v in Var, where: v.block_id == ^other.id and v.key == "heading"))
    end

    test "of two keys leaves a block's value under one new key when the block holds only the other old key", c do
      # The block holds body, and heading as a leftover with text, but no tagline
      block = first_block(c.identity)
      Repo.delete_all(from(v in Var, where: v.block_id == ^block.id and v.key == "tagline"))
      leftover!(block, "heading", "Typed later")
      rename_tagline!(c)
      rename_body!(c)

      plan = plan!(c)
      assert [%{action: :update, moves: %{renames: [_, _]}}] = plan.items
      proposed = Proposed.sync_block(load_tree(block), Proposed.build(%{plan: plan, items: plan.items}))
      assert Enum.find(proposed.vars, &(&1.key == "heading")).value == "Typed later"

      import!(c)
      assert var(block, "heading").value == "Typed later"
      assert ref(block, "copy").data.data.text == "<p>Identity 0</p>"
    end
  end

  describe "a rename is refused" do
    test "when it changes the type", c do
      rename_tagline!(c, "text")

      assert [%{action: :migration_required, reason: reason}] = plan!(c).items
      assert reason =~ ~s|var "heading" renamed from "tagline" changes type (string → text)|
      assert reason =~ "resolve --map"
    end

    test "when a block holds a value of its own under the new key, naming the blocks and entries", c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      leftover!(held, "heading", "Typed later")
      rename_tagline!(c)

      assert [%{action: :migration_required, reason: reason}] = plan!(c).items
      assert reason =~ ~s(var "heading" renamed from "tagline": blocks ##{held.id} already hold a value under heading)
      assert reason =~ "(in Identity)"

      assert_raise Mix.Error, fn -> import!(c, ["--dry-run"]) end
      assert Enum.join(shell_output(), "\n") =~ "migration_required module #{c.module.uid}"
      assert var(held, "tagline").value == "Kept words"
    end

    test "when a block holds the old key under another type", c do
      held = first_block(c.identity)
      Repo.update_all(from(v in Var, where: v.block_id == ^held.id and v.key == "tagline"), set: [type: :text])
      rename_tagline!(c)

      assert [%{action: :migration_required, reason: reason}] = plan!(c).items
      assert reason =~ "blocks ##{held.id} hold tagline as another type than heading has"
    end

    test "when a block's choice is not one of the new select's options", c do
      held = first_block(c.identity)
      Repo.update_all(from(v in Var, where: v.key == "tagline"), set: [type: :select, value: "large"])
      record = Repo.preload(module(c), [:refs, :vars], force: true)

      target = %Var{key: "size", type: :select, options: [%Var.Option{label: "Small", value: "small"}]}
      module = %{record | vars: [target]}

      assert %{refused: [reason]} = Renames.plan(record, module, [%{kind: :var, from: "tagline", to: "size"}], c.user)
      assert reason =~ "blocks ##{held.id}"
      assert reason =~ "hold a value of tagline that is not one of size's options"

      # A select without options takes no choice either
      assert %{refused: [reason]} =
               Renames.plan(
                 record,
                 %{record | vars: [%{target | options: []}]},
                 [%{kind: :var, from: "tagline", to: "size"}],
                 c.user
               )

      assert reason =~ "blocks ##{held.id}"
    end

    test "when a block's region under the new ref holds blocks, as both names own children", c do
      block = first_block(c.identity)
      footnote!(c, block, "body")
      footnote!(c, block, "copy")
      rename_body!(c)

      assert [%{action: :migration_required, reason: reason}] = plan!(c).items
      assert reason =~ ~s(ref "copy" renamed from "body": blocks ##{block.id} already hold a value under copy)
    end

    test "when the files declare it wrongly, as they are read", c do
      source = File.read!(c.exs)

      bad = [
        {~s(var "tagline", "string" do\n), ~s(var "tagline", "string" do\n      renamed_from "tagline"\n),
         "names the var itself"},
        {~s(ref "body", "text" do\n),
         ~s(ref "copy", "text" do\n      renamed_from "body"\n    end\n    ref "copy2", "text" do\n      renamed_from "body"\n),
         ~s(copy and copy2 are both renamed_from "body")}
      ]

      for {from, to, message} <- bad do
        File.write!(c.exs, String.replace(source, from, to))
        assert {:error, error} = Definitions.read(c.path)
        assert error =~ message
      end

      # A source the file still defines (`title` is not one: refs and vars are apart)
      File.write!(
        c.exs,
        String.replace(
          source,
          ~s(var "tagline", "string" do\n),
          ~s(var "heading", "string" do\n      renamed_from "tagline"\n    end\n    var "tagline", "string" do\n)
        )
      )

      assert {:error, error} = Definitions.read(c.path)
      assert error =~ ~s(renamed_from "tagline", which the file still defines)

      # A chain
      File.write!(
        c.exs,
        String.replace(
          source,
          ~s(var "tagline", "string" do\n),
          ~s(var "heading", "string" do\n      renamed_from "tagline"\n    end\n    var "title", "string" do\n      renamed_from "heading"\n)
        )
      )

      assert {:error, error} = Definitions.read(c.path)
      assert error =~ "which is itself renamed"

      # A ref and a var renamed from the same old key are apart
      File.write!(
        c.exs,
        source
        |> String.replace(~s(var "tagline", "string" do\n), ~s(var "body2", "string" do\n      renamed_from "body"\n))
        |> String.replace(~s(ref "body", "text" do\n), ~s(ref "copy", "text" do\n      renamed_from "body"\n))
      )

      assert {:ok, %{"renames" => %{} = renames}} = Definitions.read(c.path)

      assert [%{"kind" => "ref", "from" => "body", "to" => "copy"}, %{"kind" => "var", "from" => "body", "to" => "body2"}] =
               renames[c.module.uid]
    end

    test "on a table template's var", c do
      dir = Path.join(c.path, "content")

      File.write!(Path.join(dir, "prices.exs"), """
      defmodule Example.Prices do
        use Brando.Content.Definition
        kind :table_template
        uid "prices"
        name "Prices"

        vars do
          var :amount, :string do
            renamed_from "price"
          end
        end
      end
      """)

      assert {:error, error} = Definitions.read(c.path)
      assert error =~ "renamed_from is only for a module's refs and vars"
    end
  end

  describe "the apply" do
    test "rolls back the moves, revisions, Activity and baselines when the caller's step fails", c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      rename_tagline!(c)
      plan = plan!(c)
      applies = Repo.aggregate(Brando.Content.DefinitionApply, :count)
      events = Repo.aggregate(Brando.Activity.Event, :count)

      assert {:error, "the batch failed"} =
               Definitions.apply(plan, c.user,
                 in_transaction: fn _plan, _changes -> Repo.rollback("the batch failed") end
               )

      assert var(held, "tagline").value == "Kept words"
      assert var(held, "heading") == nil
      assert [%{key: "tagline"}] = Repo.preload(module(c), :vars).vars
      assert revisions(c.identity) == []
      assert Repo.aggregate(Brando.Content.DefinitionApply, :count) == applies
      assert Repo.aggregate(Brando.Activity.Event, :count) == events

      # The same files plan the same update again
      assert [%{action: :update, moves: %{renames: [_]}}] = plan!(c).items
    end

    test "refuses what changed since the review: a value typed under the new key in between", c do
      held = first_block(c.identity)
      leftover!(held, "heading", "")
      rename_tagline!(c)
      plan = plan!(c)

      Repo.update_all(from(v in Var, where: v.block_id == ^held.id and v.key == "heading"), set: [value: "Typed since"])

      assert {:error, reason} = Definitions.apply(plan, c.user)
      assert reason =~ "content changed since you reviewed it"
      assert reason =~ "review again"
      assert var(held, "heading").value == "Typed since"
    end

    test "that Postgres aborts as a deadlock is an error to try again, not a crash", c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      rename_tagline!(c)
      plan = plan!(c)

      deadlock = fn _plan, _changes ->
        Repo.repo().query!("DO $$ BEGIN RAISE EXCEPTION USING ERRCODE = '40P01'; END $$")
      end

      assert {:error, reason} = Definitions.apply(plan, c.user, in_transaction: deadlock)
      assert reason =~ ~r/try again/i
      assert var(held, "tagline").value == "Kept words"
      assert [%{action: :update}] = plan!(c).items
    end

    test "is retried after the commit without moving again: a refresh adds no revisions", c do
      c.identity |> first_block() |> set!("tagline", "Kept words")
      rename_tagline!(c)
      import!(c)
      assert length(revisions(c.identity)) == 2

      {:ok, _} = Definitions.refresh([c.module.uid], c.user)
      assert [%{action: :noop}] = plan!(c).items
      assert length(revisions(c.identity)) == 2
    end
  end

  describe "where the new key is defined already" do
    test "the apply keeps the old one as a leftover, and prints the resolve --map line that moves it", c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      # Added here before: this environment has both, and its files say so
      Repo.insert!(%Var{module_id: c.module.id, key: "heading", type: :string, label: %{"en" => "Heading"}, sequence: 1})
      path = c.path <> "-both"
      {:ok, _} = Definitions.export(path, c.user, uids: [c.module.uid])
      on_exit(fn -> File.rm_rf!(path) end)
      c = %{c | path: path, exs: Path.join(path, "content/teaser.exs")}

      without = Regex.replace(~r/    var "tagline", "string" do\n.*?\n    end\n/s, File.read!(c.exs), "")
      File.write!(c.exs, without)
      edit!(c, ~s(var "heading", "string" do\n), ~s(var "heading", "string" do\n      renamed_from "tagline"\n))
      edit_template!(c, "{{ tagline }}", "{{ heading }}")

      [item] = plan!(c).items
      assert item.moves == nil
      assert [%{kind: :var, from: "tagline", to: "heading", ok?: true}] = item.remaps

      output = import!(c)
      resolve = Enum.find_value(output, &(String.starts_with?(&1, "  resolve: ") && String.trim_leading(&1)))

      assert resolve ==
               "resolve: mix brando.modules resolve --uid #{c.module.uid} --user #{c.user.id} --map var:tagline=heading --apply"

      assert var(held, "tagline").value == "Kept words"
      resolve |> String.split() |> Enum.drop(3) |> run_task()
      assert var(held, "heading").value == "Kept words"

      # Once resolved, no plan prints it again
      refute Enum.any?(import!(c, ["--dry-run"]), &(&1 =~ "resolve:"))
    end

    test "the resolve --map line is not offered when it would replace a value or leave a ref's slots", c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      record = Repo.preload(module(c), [:refs, :vars])
      tagline = [%{kind: :var, from: "tagline", to: "heading"}]
      module = %{record | vars: [%Var{key: "heading", type: :string, label: %{"en" => "Heading"}}]}
      assert [%{ok?: true}] = Renames.remaps(record, module, tagline)

      leftover!(held, "heading", "Typed later")
      assert [%{ok?: false}] = Renames.remaps(record, module, tagline)

      [body] = record.refs
      body_to_copy = [%{kind: :ref, from: "body", to: "copy"}]
      module = %{record | refs: [%{body | name: "copy"}]}
      assert [%{ok?: true}] = Renames.remaps(record, module, body_to_copy)

      footnote!(c, held, "body")
      assert [%{ok?: false}] = Renames.remaps(record, module, body_to_copy)
    end
  end

  describe "a release" do
    setup c do
      File.rm!(Path.join(c.path, "modules.lock.json"))
      assert {:ok, %{adopted: 1}} = Release.plan(path: c.path, version: "1.0.0")
      :ok
    end

    test "verifies a pure rename as unchanged, records the moves and can't revert them", c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      rename_tagline!(c)
      opts = [path: c.path, version: "2.0.0", user: c.user.id]

      {:ok, report} = Release.plan(opts)
      assert %{verdict: :same} = Verify.check(Page, c.identity.id, Proposed.build(report))

      {:ok, %{batch_id: batch_id}} =
        Release.apply(:all, opts ++ [wait: false, renames: Release.renames_digest(report)])

      assert var(held, "heading").value == "Kept words"
      [before | _] = revisions(c.identity)
      assert before.description == "Before release 2.0.0: var tagline → heading in Teaser"

      batch = Batches.get(batch_id)

      assert [%{"uid" => uid, "moves" => [%{"kind" => "var", "from" => "tagline", "to" => "heading"}]}] =
               batch.definitions["items"]

      assert uid == c.module.uid

      assert {:ok, %{revert: [], irreversible: [%{reason: "the apply moved values from tagline to heading"}]}} =
               Batches.preview(batch, c.user)

      assert {:error, :needs_migration} = Batches.revert(batch, c.user)
      assert var(held, "heading").value == "Kept words"
    end

    test "previews a conflict the operator takes the release's version of with the values moved, as the apply moves them",
         c do
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      rename_tagline!(c)
      # Edited here since the last release
      Repo.update_all(from(m in Module, where: m.id == ^c.module.id), set: [class: "edited-here"])
      opts = [path: c.path, version: "2.0.0", user: c.user.id]

      {:ok, report} = Release.plan(opts)
      assert [%{action: :conflict, state: :changed_in_both}] = report.items
      proposed = Proposed.build(report, conflicts: [c.module.uid])
      synced = Proposed.sync_block(load_tree(held), proposed)
      assert Enum.find(synced.vars, &(&1.key == "heading")).value == "Kept words"
      assert %{verdict: :same} = Verify.check(Page, c.identity.id, proposed)

      {:ok, _} = Release.apply(:all, opts ++ [wait: false, discard: [c.module.uid]])
      assert var(held, "heading").value == "Kept words"
    end

    test "records no moves, and can revert, when no block held the old key", c do
      Repo.delete_all(from(v in Var, where: v.key == "tagline" and not is_nil(v.block_id)))
      rename_tagline!(c)
      opts = [path: c.path, version: "2.0.0", user: c.user.id]

      {:ok, %{batch_id: batch_id}} = Release.apply(:all, opts ++ [wait: false])
      batch = Batches.get(batch_id)
      assert [item] = batch.definitions["items"]
      refute Map.has_key?(item, "moves")
      assert {:ok, %{revert: [_], irreversible: []}} = Batches.preview(batch, c.user)
    end

    test "refuses an apply whose renames changed after the review", c do
      rename_tagline!(c)
      opts = [path: c.path, version: "2.0.0", user: c.user.id]
      {:ok, report} = Release.plan(opts)
      reviewed = Release.renames_digest(report)
      fingerprint = Verify.fingerprint(report)

      edit!(c, ~s(var "heading", "string" do\n      renamed_from "tagline"\n), ~s(var "heading", "string" do\n))
      {:ok, changed} = Release.plan(opts)
      assert Verify.fingerprint(changed) != fingerprint

      assert {:error, message} = Release.apply(:all, opts ++ [wait: false, renames: reviewed])
      assert message =~ "review it again"
      assert [%{key: "tagline"}] = Repo.preload(module(c), :vars).vars
    end
  end

  describe "the moves are scoped" do
    test "to this module's blocks, not a shared library module's with the same id", c do
      shared = first_block(c.naming)
      Repo.update_all(from(b in Block, where: b.id == ^shared.id), set: [module_origin: :shared])
      rename_tagline!(c)

      assert [%{moves: %{blocks: 5}}] = plan!(c).items
      import!(c)
      assert var(shared, "tagline").value == "Default tagline"
      assert var(shared, "heading") == nil
    end

    test "to the modules a release applies: one of two renamed modules", c do
      card =
        ProposalFixtures.module!(c.user, "Card", "<p>{{ title }}</p>",
          vars: [%{type: "string", key: "title", label: "Title", value: "Default title"}]
        )

      cards = ProposalFixtures.page!(c.user, "Cards", card)
      card.id |> Blocks.list_block_ids_using_module() |> Blocks.sync_blocks(card.id)
      card_block = cards |> first_block() |> set!("title", "Card words")

      path = c.path <> "-two"
      {:ok, _} = Definitions.export(path, c.user, uids: [c.module.uid, card.uid])
      on_exit(fn -> File.rm_rf!(path) end)
      File.rm!(Path.join(path, "modules.lock.json"))
      assert {:ok, %{adopted: 2}} = Release.plan(path: path, version: "1.0.0")

      c = %{c | path: path, exs: Path.join(path, "content/teaser.exs")}
      held = c.identity |> first_block() |> set!("tagline", "Kept words")
      rename_tagline!(c)
      card_exs = Path.join(path, "content/card.exs")

      File.write!(
        card_exs,
        String.replace(
          File.read!(card_exs),
          ~s(var "title", "string" do\n),
          ~s(var "name", "string" do\n      renamed_from "title"\n)
        )
      )

      {:ok, _} = Release.apply([c.module.uid], path: path, version: "2.0.0", user: c.user.id, wait: false)
      assert var(held, "heading").value == "Kept words"
      assert var(card_block, "title").value == "Card words"
      assert var(card_block, "name") == nil
      assert [%{key: "title"}] = Repo.preload(Repo.get!(Module, card.id), :vars).vars
    end

    test "to as many blocks as an apply moves while editors' saves wait, counted before they are loaded", c do
      bare_blocks!(c, c.module, "tagline", 1500)
      rename_tagline!(c)

      assert [%{action: :migration_required, moves: %{entries: []}, reason: reason}] = plan!(c).items
      assert reason =~ "would move values in 1506 blocks,"
      assert reason =~ "mix brando.modules resolve --map var:tagline=heading"
    end

    test "to as many blocks across the modules an apply selects", c do
      card =
        ProposalFixtures.module!(c.user, "Card", "<p>{{ title }}</p>",
          vars: [%{type: "string", key: "title", label: "Title", value: "Default title"}]
        )

      bare_blocks!(c, c.module, "tagline", 750)
      bare_blocks!(c, card, "title", 750)

      path = c.path <> "-limit"
      {:ok, _} = Definitions.export(path, c.user, uids: [c.module.uid, card.uid])
      on_exit(fn -> File.rm_rf!(path) end)
      c = %{c | path: path, exs: Path.join(path, "content/teaser.exs")}
      rename_tagline!(c)
      card_exs = Path.join(path, "content/card.exs")

      File.write!(
        card_exs,
        String.replace(
          File.read!(card_exs),
          ~s(var "title", "string" do\n),
          ~s(var "name", "string" do\n      renamed_from "title"\n)
        )
      )

      # Each module alone is within the limit; the two together are not
      items = plan!(c).items
      assert [%{action: :migration_required, reason: reason}, %{action: :migration_required}] = items
      assert reason =~ "would move values in 1506 blocks of 2 entries"

      {:ok, bundle} = Definitions.read(path)
      assert {:ok, plan} = Definitions.plan(bundle, c.user, select: [c.module.uid])
      assert %{action: :update} = Enum.find(plan.items, &(&1.uid == c.module.uid))
    end
  end

  describe "a revert of a batch whose apply moved values" do
    test "leaves out the renamed module's tree, a sibling changed with it, and reverts an unrelated module", c do
      parent = ProposalFixtures.module!(c.user, "Row", "<div>{{ content }}</div>", multi: true)

      child =
        ProposalFixtures.module!(c.user, "Cell", "<p>{{ caption }}</p>",
          parent_id: parent.id,
          vars: [%{type: "string", key: "caption", label: "Caption", value: "Default caption"}]
        )

      sibling = ProposalFixtures.module!(c.user, "Other cell", "<p>Other</p>", parent_id: parent.id)
      held = child_block!(c, child, "Cell words")

      path = c.path <> "-tree"
      {:ok, _} = Definitions.export(path, c.user, uids: [parent.uid, c.module.uid])
      on_exit(fn -> File.rm_rf!(path) end)
      File.rm!(Path.join(path, "modules.lock.json"))
      assert {:ok, %{adopted: 4}} = Release.plan(path: path, version: "1.0.0")

      # Each change in the file that holds `from`
      write = fn from, to ->
        [file] =
          path |> Path.join("content/**/*.{exs,liquid}") |> Path.wildcard() |> Enum.filter(&(File.read!(&1) =~ from))

        File.write!(file, String.replace(File.read!(file), from, to))
      end

      write.(~s(var "caption", "string" do\n), ~s(var "text", "string" do\n      renamed_from "caption"\n))
      write.("{{ caption }}", "{{ text }}")
      write.("<p>Other</p>", "<p>Other, changed</p>")
      write.("<p>{{ tagline }}</p>", "<h2>{{ tagline }}</h2>")

      opts = [path: path, version: "2.0.0", user: c.user.id, wait: false]
      {:ok, %{batch_id: batch_id}} = Release.apply(:all, opts)
      assert var(held, "text").value == "Cell words"

      assert {:ok, %{reverted: reverted, irreversible: [%{uid: irreversible}]}} =
               Batches.revert(Batches.get(batch_id), c.user)

      assert irreversible == child.uid
      assert Enum.map(reverted, & &1.uid) == [c.module.uid]
      assert Repo.get!(Module, c.module.id).code =~ "<p>{{ tagline }}</p>"
      assert Repo.get!(Module, sibling.id).code =~ "Other, changed"
      assert var(held, "text").value == "Cell words"
    end
  end

  describe "a refusal names the entries the person may open" do
    test "and counts the others", c do
      held = first_block(c.identity)
      leftover!(held, "heading", "Typed later")
      record = Repo.preload(module(c), [:refs, :vars])
      module = %{record | vars: [%Var{key: "heading", type: :string}]}
      rename = [%{kind: :var, from: "tagline", to: "heading"}]

      assert %{refused: [named]} = Renames.plan(record, module, rename, c.user)
      assert named =~ "(in Identity)"

      put_test_env(:authorization_mode, :groups)
      assert {:ok, _} = Brando.Authorization.Migration.run()
      nobody = Brando.Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
      assert %{refused: [counted]} = Renames.plan(record, module, rename, nobody)
      refute counted =~ "Identity"
      assert counted =~ "(in 1 entry you cannot open)"
    end
  end

  describe "BlockMoves.content?/2" do
    test "judges by the stored fields: a link's target setting and a form are choices; a copied default ref is not" do
      default = %Var{type: :link, key: "cta", value: "https://a", link_text: "Read", link_target_blank: false}

      refute BlockMoves.content?(%{default | id: 1}, default)
      refute BlockMoves.content?(%Var{type: :link, key: "cta", value: "", link_text: nil}, default)
      assert BlockMoves.content?(%{default | link_target_blank: true}, default)
      assert BlockMoves.content?(%{default | value: "https://b"}, default)
      assert BlockMoves.content?(%Var{type: :form, key: "form", form_id: 4}, %Var{type: :form, key: "form"})

      data = %Brando.Villain.Blocks.TextBlock{data: %Brando.Villain.Blocks.TextBlock.Data{text: "Default"}}
      source = %Ref{name: "body", uid: "a", data: data}
      refute BlockMoves.content?(%Ref{name: "body", uid: "b", data: data}, source)

      typed = put_in(data.data.text, "Typed")
      assert BlockMoves.content?(%Ref{name: "body", uid: "b", data: typed}, source)
    end
  end

  describe "a ref returning over a leftover of another type" do
    test "needs a migration", c do
      block = first_block(c.identity)
      source = File.read!(c.exs)
      without_body = Regex.replace(~r/\n  refs do\n.*?\n  end\n/s, source, "")
      File.write!(c.exs, without_body)
      edit_template!(c, "{% ref refs.body %}", "")
      import!(c)

      # Back as a header, over the text the blocks keep
      header = """

        refs do
          ref "body", "header" do
            default %{"text" => "A heading"}
          end
        end
      """

      File.write!(c.exs, Regex.replace(~r/\n  refs do\n.*?\n  end\n/s, source, header))
      edit_template!(c, "", "")

      assert [%{action: :migration_required, reason: reason}] = plan!(c).items
      assert reason =~ ~s(ref "body" returns as header while blocks ##{block.id})
    end
  end

  ## Fixtures

  # `count` blocks of `module` in no entry, each holding `key`
  defp bare_blocks!(c, module, key, count) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    blocks =
      for _ <- 1..count do
        %{
          uid: Brando.Utils.generate_uid(),
          type: :module,
          module_id: module.id,
          module_origin: :local,
          creator_id: c.user.id,
          inserted_at: now,
          updated_at: now
        }
      end

    {_, inserted} = Repo.insert_all(Block, blocks, returning: [:id])

    Repo.insert_all(
      Var,
      for(
        %{id: id} <- inserted,
        do: %{block_id: id, key: key, type: :string, label: %{"en" => key}, inserted_at: now, updated_at: now}
      )
    )
  end

  defp leftover!(block, key, value) do
    Repo.insert!(%Var{block_id: block.id, key: key, type: :string, label: %{"en" => key}, value: value})
  end

  # A footnote under the block's `ref` text ref, holding one Teaser block
  defp footnote!(c, block, ref) do
    slot =
      Repo.insert!(%Block{
        uid: Brando.Utils.generate_uid(),
        type: :slot,
        slot_kind: :footnote,
        slot_name: ref,
        slot_module_set: "all",
        parent_id: block.id,
        creator_id: c.user.id,
        source: block.source
      })

    Repo.insert!(%Block{
      uid: Brando.Utils.generate_uid(),
      type: :module,
      module_id: c.module.id,
      parent_id: slot.id,
      creator_id: c.user.id,
      source: block.source
    })

    slot
  end

  defp child_block!(c, module, caption) do
    page = Brando.Factory.insert(:page, creator: c.user, title: "Grid", uri: "grid")

    row =
      Repo.insert!(%Block{
        uid: Brando.Utils.generate_uid(),
        type: :module,
        multi: true,
        module_id: module.parent_id,
        creator_id: c.user.id,
        source: Page.Blocks
      })

    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: row.id, sequence: 0})

    cell =
      Repo.insert!(%Block{
        uid: Brando.Utils.generate_uid(),
        type: :module_entry,
        module_id: module.id,
        parent_id: row.id,
        creator_id: c.user.id,
        source: Page.Blocks
      })

    Repo.insert!(%Var{block_id: cell.id, key: "caption", type: :string, label: %{"en" => "Caption"}, value: caption})
    cell
  end

  defp load_tree(block) do
    Repo.preload(Repo.get!(Block, block.id), [:vars, refs: Ref.preloads(), children: [:children]])
  end
end
