defmodule Brando.Content.DefinitionRemovalsTest do
  # brandocms/brando#3540: a definition file that removes a ref or var is an
  # update, in an import and in a release. The blocks keep what they hold in
  # it as a leftover, as after the same save in the admin, and the plan
  # prints the `resolve` command that clears them.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  @moduletag :capture_log

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.{Block, Blocks, Definitions, Module, Var}
  alias Brando.Content.Definitions.Release
  alias Brando.Content.Definitions.Release.{Batches, Review}
  alias Brando.Content.StaleBlocks
  alias Brando.ProposalFixtures
  alias Brando.Repo
  alias Brando.Pages.Page

  setup do
    user = Brando.Factory.insert(:random_user)

    module =
      ProposalFixtures.module!(user, "Teaser", "<p>{{ tagline }}</p>{% ref refs.body %}",
        refs: [ProposalFixtures.ref("body", %{type: "text", data: %{text: "Default body"}})],
        vars: [%{type: "string", key: "tagline", label: "Tagline", value: "Default tagline"}]
      )

    identity = ProposalFixtures.page!(user, "Identity", module)
    naming = ProposalFixtures.page!(user, "Naming", module)

    path = Path.join(System.tmp_dir!(), "brando-removals-#{System.unique_integer([:positive])}")
    {:ok, _} = Definitions.export(path, user, uids: [module.uid])
    on_exit(fn -> File.rm_rf!(path) end)

    %{user: user, module: module, identity: identity, naming: naming, path: path, exs: Path.join(path, "content/teaser.exs")}
  end

  # The first block of `page` holds `value` in a `tagline` var
  defp hold!(page, value, type \\ :string) do
    block = page |> blocks() |> hd()
    Repo.insert!(%Var{block_id: block.id, key: "tagline", type: type, label: %{"en" => "Tagline"}, value: value})
    block
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

  defp var(block, key), do: Repo.get_by(Var, block_id: block.id, key: key)
  defp module(c), do: Repo.get!(Module, c.module.id)

  # The file without its vars, or with `vars` in their place
  defp edit_vars!(c, vars \\ "") do
    source = File.read!(c.exs)
    edited = Regex.replace(~r/\n  vars do\n.*?\n  end\n/s, source, vars)
    assert edited != source
    File.write!(c.exs, edited)
  end

  defp var_block(key, type), do: "\n  vars do\n    var :#{key}, :#{type} do\n      label \"#{key}\"\n    end\n  end\n"

  defp edit_template!(c, from, to) do
    file = Path.join(c.path, "content/teaser.liquid")
    File.write!(file, String.replace(File.read!(file), from, to))
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

  describe "an import that removes a var" do
    test "is an update; the blocks keep the value until the printed resolve drops it", c do
      holder = hold!(c.identity, "Kept words")
      edit_vars!(c)

      output = import!(c)
      uid = c.module.uid
      assert "update module #{uid}: removes var tagline (1 of 6 blocks hold it, 1 entry)" in output
      resolve = "mix brando.modules resolve --uid #{uid} --user #{c.user.id} --drop var:tagline --apply"
      assert "  resolve: " <> resolve in output

      assert Repo.preload(module(c), :vars).vars == []
      assert var(holder, "tagline").value == "Kept words"
      assert Blocks.list_stale_block_ids(module(c)) == [holder.id]

      output = resolve |> String.split() |> Enum.drop(2) |> run_task()
      assert Enum.any?(output, &(&1 =~ "Resolved 1 blocks; 1 are now on version"))
      assert var(holder, "tagline") == nil
      assert Blocks.list_stale_block_ids(module(c)) == []

      assert Enum.any?(import!(c), &(&1 =~ "noop module #{uid}"))
    end

    test "that no block holds prints no resolve line", c do
      edit_vars!(c)

      output = import!(c, ["--dry-run"])
      assert "update module #{c.module.uid}: removes var tagline (none of 6 blocks hold it)" in output
      refute Enum.any?(output, &(&1 =~ "resolve:"))
    end

    test "and adds another is a rename that resolve --map finishes; the page renders the value under the new key", c do
      holder = hold!(c.identity, "Kept words")
      edit_vars!(c, var_block("strapline", "string"))
      edit_template!(c, "{{ tagline }}", "{{ strapline }}")

      assert [%{action: :update, removes: %{keys: [var: "tagline"], blocks: 1}}] = plan!(c).items
      import!(c)
      assert var(holder, "strapline").value in [nil, ""]

      run_task(~w(resolve --uid #{c.module.uid} --user #{c.user.id} --map tagline=strapline --apply))
      assert var(holder, "strapline").value == "Kept words"
      assert var(holder, "tagline") == nil
      assert Repo.get!(Page, c.identity.id).rendered_blocks =~ "<p>Kept words</p>"
    end
  end

  describe "still needs a migration" do
    test "a retyped var", c do
      hold!(c.identity, "Kept words")
      edit_vars!(c, var_block("tagline", "text"))

      assert [%{action: :migration_required, reason: reason}] = plan!(c).items
      assert reason =~ ~s(Variable "tagline" changed from string to text)
    end

    test "a key that comes back with another type over a leftover; with the same type, the value comes back", c do
      holder = hold!(c.identity, "Kept words")
      source = File.read!(c.exs)
      edit_vars!(c)
      import!(c)

      retyped = String.replace(source, ~s(var "tagline", "string"), ~s(var "tagline", "text"))
      assert retyped != source
      File.write!(c.exs, retyped)
      assert [%{action: :migration_required, reason: reason}] = plan!(c).items
      assert reason =~ ~s(var "tagline" returns as text while blocks ##{holder.id} hold a leftover of another type)

      File.write!(c.exs, source)
      assert [%{action: :update, removes: nil}] = plan!(c).items
      import!(c)
      assert var(holder, "tagline").value == "Kept words"
      assert Blocks.list_stale_block_ids(module(c)) == []
    end
  end

  describe "a release that removes a var" do
    setup c do
      File.rm!(Path.join(c.path, "modules.lock.json"))
      assert {:ok, %{adopted: 1}} = Release.plan(path: c.path, version: "1.0.0")
      :ok
    end

    defp lines(fun) do
      {:ok, agent} = Agent.start_link(fn -> [] end)
      fun.(fn line -> Agent.update(agent, &[line | &1]) end)
      agent |> Agent.get(& &1) |> Enum.reverse()
    end

    test "plans as an update with the resolve line, applies, and a revert brings the values back", c do
      holder = hold!(c.identity, "Kept words")
      edit_vars!(c)
      opts = [path: c.path, version: "2.0.0", user: c.user.id]

      text = lines(&Release.status(Keyword.put(opts, :info, &1)))
      assert "  update module Teaser (#{c.module.uid}): removes var tagline (1 of 6 blocks hold it, 1 entry)" in text

      assert "    resolve: mix brando.modules resolve --uid #{c.module.uid} --user #{c.user.id} --drop var:tagline --apply" in text

      {:ok, report} = Release.plan(opts)
      assert [%{group: :ready, status: :update, class: :destructive}] = Review.rows(report)

      {:ok, %{batch_id: batch_id}} = Release.apply(:all, Keyword.put(opts, :wait, false))
      assert Repo.preload(module(c), :vars).vars == []
      assert var(holder, "tagline").value == "Kept words"
      assert StaleBlocks.count(module(c)) == 1

      assert {:ok, %{reverted: [_], conflicts: []}} = Batches.revert(Batches.get(batch_id), c.user)
      assert [%{key: "tagline"}] = Repo.preload(module(c), :vars).vars
      assert var(holder, "tagline").value == "Kept words"
      assert StaleBlocks.count(module(c)) == 0
    end
  end
end
